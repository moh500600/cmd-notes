// UI harness: boots the real app on an in-memory database (with field encryption on)
// as an offline user, loads the demo data through the real repository, and
// renders every screen in Arabic and English (phone, desktop side rail, dark theme).
// Any Flutter error (overflow, exception) or a missing translation fails it.
// With SCREENSHOTS=1 it writes PNGs to build/screens/.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_pro/app.dart';
import 'package:notes_pro/core/l10n/l10n.dart';
import 'package:notes_pro/data/db/app_database.dart';
import 'package:notes_pro/data/db/search_index.dart';
import 'package:notes_pro/data/security/field_cipher.dart';
import 'package:notes_pro/data/security/key_vault.dart';
import 'package:notes_pro/presentation/providers/providers.dart';
import 'package:notes_pro/presentation/screens/calendar/calendar_screen.dart';
import 'package:notes_pro/presentation/screens/editor/note_editor_screen.dart';
import 'package:notes_pro/presentation/screens/journal/journal_screen.dart';
import 'package:notes_pro/presentation/screens/notebooks/notebooks_screen.dart';
import 'package:notes_pro/presentation/screens/notes/notes_list_screen.dart';
import 'package:notes_pro/presentation/screens/search/search_screen.dart';
import 'package:notes_pro/presentation/screens/settings/demo_data.dart';
import 'package:notes_pro/presentation/screens/settings/settings_screen.dart';
import 'package:notes_pro/presentation/screens/sharing/shared_screen.dart';
import 'package:notes_pro/presentation/screens/tags/tags_screen.dart';
import 'package:notes_pro/presentation/screens/templates/templates_screen.dart';
import 'package:notes_pro/presentation/screens/voice/voice_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final shots = Platform.environment['SCREENSHOTS'] == '1';
final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final tajawal = FontLoader('Tajawal');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Tajawal-$w.ttf');
    if (f.existsSync()) tajawal.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await tajawal.load();
  final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  if (mono.existsSync()) {
    await (FontLoader('Roboto Mono')..addFont(Future.value(ByteData.sublistView(mono.readAsBytesSync())))).load();
  }
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

final _errs = <String>[];
void Function(FlutterErrorDetails)? _origOnError;

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  if (_errs.isNotEmpty) {
    final all = _errs.join('\n----\n');
    _errs.clear();
    FlutterError.onError = _origOnError;
    fail('UI errors on/before $name:\n$all');
  }
  if (!shots) return;
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('build/screens/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  sqfliteFfiInit();
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
    await _loadFonts();
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('every screen renders with real data ($lang)', (tester) async {
      if (shots) debugDisableShadows = false;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      final ar = lang == 'ar';
      _origOnError = FlutterError.onError;
      FlutterError.onError = (d) => _errs.add(d.toString());
      L10n.missing.clear();
      addTearDown(() => FlutterError.onError = _origOnError);
      void step(String s) => stderr.writeln('[$lang] $s');

      SharedPreferences.setMockInitialValues({'settings_v1': jsonEncode({'lang': lang, 'theme': ThemeMode.light.index})});
      final prefs = await SharedPreferences.getInstance();
      late Database db;
      late SearchIndex index;
      await tester.runAsync(() async {
        db = await AppDatabase.open(databaseFactoryFfiNoIsolate, 'file:smoke_$lang?mode=memory&cache=shared');
        index = SearchIndex(db);
        await index.init();
      });
      final cipher = AesGcmFieldCipher(AesGcmFieldCipher.newKey());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          prefsProvider.overrideWithValue(prefs),
          searchIndexProvider.overrideWithValue(index),
          cipherProvider.overrideWithValue(cipher),
          keyLocationProvider.overrideWithValue(KeyLocation.secureStorage),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: _boundary, child: const NotesProApp()),
        ),
      );
      await tester.pump();

      Future<void> settle([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 120));
        }
      }

      await settle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await _shot(tester, '${lang}_01_empty_dashboard');
      await tester.runAsync(() => loadDemoData(container.read(repoProvider)!, ar: ar));
      await settle(12);
      await _shot(tester, '${lang}_02_dashboard');

      // journal text is ciphertext in SQLite
      final raw = await tester.runAsync(() => db.query('journal_entries'));
      expect(raw!.first['plain_text'], startsWith(FieldCipher.prefix));

      final d = (await tester.runAsync(() => container.read(notesProvider.future)))!;
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      var n = 3;
      Future<void> open(Widget w, String name, {Future<void> Function()? act}) async {
        step(name);
        nav.push(MaterialPageRoute(builder: (_) => w));
        await settle();
        if (act != null) await act();
        await _shot(tester, '${lang}_${(n++).toString().padLeft(2, '0')}_$name');
        expect(tester.takeException(), isNull, reason: name);
        nav.pop();
        await settle(4);
      }

      final lecture = d.active.firstWhere((x) => x.type == 'study');
      final meeting = d.active.firstWhere((x) => x.type == 'meeting');
      final code = d.active.firstWhere((x) => x.type == 'code');
      await open(const NotesListScreen(), 'notes');
      await open(NoteEditorScreen(noteId: lecture.id), 'editor_lecture');
      await open(NoteEditorScreen(noteId: meeting.id), 'editor_meeting');
      await open(NoteEditorScreen(noteId: code.id), 'editor_code');
      // editing through the UI: type into the title, autosave, counters
      nav.push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: meeting.id)));
      await settle();
      await tester.enterText(find.byKey(const Key('note_title')), ar ? 'اجتماع الفريق الأسبوعي' : 'Weekly team meeting');
      await settle();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 1300)));
      await settle();
      final saved = (await tester.runAsync(() => container.read(repoProvider)!.note(meeting.id)))!;
      expect(saved.title, ar ? 'اجتماع الفريق الأسبوعي' : 'Weekly team meeting');
      nav.pop();
      await settle(4);

      await open(const NotebooksScreen(), 'notebooks');
      await open(NotebookScreen(notebookId: d.notebooks.firstWhere((x) => x.parentId == null && x.pinned).id), 'notebook');
      await open(const TagsScreen(), 'tags');
      await open(const TemplatesScreen(), 'templates');
      await open(const VoiceScreen(), 'voice');
      await open(
        const SearchScreen(),
        'search',
        act: () async {
          await tester.enterText(find.byKey(const Key('search_field')), ar ? 'مشروع' : 'project');
          await settle();
        },
      );
      await open(const JournalScreen(), 'journal');
      await open(JournalEntryScreen(day: DateTime.now()), 'journal_entry');
      await open(const CalendarScreen(), 'calendar');
      await open(const SharedScreen(), 'shared');
      await open(const SettingsScreen(), 'settings');
      await open(const NotesListScreen(filter: NoteFilter('trash')), 'trash');
      await open(
        const NotesListScreen(),
        'quick_create',
        act: () async {
          await tester.tap(find.byKey(const Key('new_note_fab')));
          await settle();
        },
      );
      nav.pop(); // the sheet was popped above; now the list itself
      await settle(4);

      // dark theme
      step('dark');
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(() => container.read(settingsProvider.notifier).update(container.read(settingsProvider).copyWith(theme: ThemeMode.dark)));
      await settle();
      await _shot(tester, '${lang}_${n++}_dashboard_dark');
      nav.push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: lecture.id)));
      await settle();
      await _shot(tester, '${lang}_${n++}_editor_dark');
      nav.pop();
      await settle(4);
      await tester.runAsync(() => container.read(settingsProvider.notifier).update(container.read(settingsProvider).copyWith(theme: ThemeMode.light)));

      // desktop: side rail
      try {
      step('desktop');
      tester.view.physicalSize = const Size(1440 * 1.5, 900 * 1.5);
      tester.view.devicePixelRatio = 1.5;
      await settle();
      expect(find.byType(NavigationRail), findsOneWidget);
      await _shot(tester, '${lang}_${n++}_desktop_dashboard');
      for (final k in ['notes', 'notebooks', 'journal']) {
        await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(L10n(lang).tr(k))));
        await settle();
        await _shot(tester, '${lang}_${n++}_desktop_$k');
      }
      nav.push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: lecture.id)));
      await settle();
      await _shot(tester, '${lang}_${n++}_desktop_editor');
      nav.pop();
      await settle(4);

      } catch (e, s) {
        stderr.writeln('DESKTOP FAIL: $e\n$s\n${_errs.join('\n---\n')}');
        rethrow;
      }
      step('done ${L10n.missing}');
      expect(L10n.missing, isEmpty, reason: 'untranslated keys');
      expect(tester.takeException(), isNull);
      FlutterError.onError = _origOnError;
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(() => db.close());
      debugDisableShadows = true;
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/l10n.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/autosave_bus.dart';
import 'domain/services/notes_data.dart';
import 'presentation/providers/providers.dart';
import 'presentation/screens/lock/lock_screen.dart';
import 'presentation/screens/shell/home_shell.dart';

class NotesProApp extends ConsumerStatefulWidget {
  const NotesProApp({super.key});
  @override
  ConsumerState<NotesProApp> createState() => _NotesProAppState();
}

class _NotesProAppState extends ConsumerState<NotesProApp> with WidgetsBindingObserver {
  Timer? _remindersDebounce;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  String? _startedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationServiceProvider).init();
      await _startup();
    });
  }

  /// Once per signed-in user: recover unsaved drafts (crash), build the search index if
  /// needed, purge expired trash, then sync.
  Future<void> _startup() async {
    final repo = ref.read(repoProvider);
    if (repo == null || _startedFor == repo.uid) return;
    _startedFor = repo.uid;
    try {
      final recovered = await repo.recoverDrafts();
      final indexed = await repo.store.db.rawQuery('SELECT COUNT(*) AS c FROM search_fts WHERE user_id = ?', [repo.uid]);
      final notes = await repo.store.db.rawQuery('SELECT COUNT(*) AS c FROM notes WHERE user_id = ? AND deleted = 0', [repo.uid]);
      if ((indexed.first['c'] as int) == 0 && (notes.first['c'] as int) > 0) await repo.reindexAll();
      await repo.purgeExpiredTrash(await repo.load(), DateTime.now());
      if (recovered.isNotEmpty) {
        ref.read(revisionProvider.notifier).bump();
        final l = L10n(ref.read(settingsProvider).lang);
        _messenger.currentState?.showSnackBar(SnackBar(content: Text(l.tr('drafts_recovered', {'n': '${recovered.length}'}))));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _remindersDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(lockProvider.notifier).resumed();
      case AppLifecycleState.inactive || AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        // Crash safety: whatever is typed reaches the database before the OS may kill the app.
        AutosaveBus.flushAll();
        if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) ref.read(lockProvider.notifier).paused();
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await AutosaveBus.flushAll();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final locked = ref.watch(lockProvider);
    ref.listen(repoProvider, (_, _) => WidgetsBinding.instance.addPostFrameCallback((_) => _startup()));
    // Re-plan OS reminders a moment after the data changes.
    ref.listen<AsyncValue<NotesData>>(notesProvider, (_, next) {
      final d = next.value;
      if (d == null || d.uid.isEmpty) return;
      _remindersDebounce?.cancel();
      _remindersDebounce = Timer(const Duration(seconds: 2), () => rescheduleReminders(ref, d));
    });
    final font = s.font == 'system' ? null : 'Tajawal';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      title: s.lang == 'ar' ? 'CMD Notes' : 'CMD Notes',
      theme: AppTheme.light(accent: s.accent, font: font),
      darkTheme: AppTheme.dark(accent: s.accent, font: font),
      themeMode: s.theme,
      locale: Locale(s.lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(s.textScale)),
        child: child ?? const SizedBox(),
      ),
      home: locked ? const LockScreen() : const HomeShell(),
    );
  }
}

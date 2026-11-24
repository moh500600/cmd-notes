import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/file_service.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../calendar/calendar_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../editor/note_editor_screen.dart';
import '../journal/journal_screen.dart';
import '../notebooks/notebooks_screen.dart';
import '../notes/notes_list_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../sharing/shared_screen.dart';
import '../tags/tags_screen.dart';
import '../templates/templates_screen.dart';
import '../voice/voice_screen.dart';

class _Dest {
  final String key;
  final IconData icon, selected;
  final Widget Function() page;
  const _Dest(this.key, this.icon, this.selected, this.page);
}

final _all = <_Dest>[
  _Dest('home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, () => const DashboardScreen()),
  _Dest('notes', Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded, () => const NotesListScreen(embedded: true)),
  _Dest('search', Icons.search_rounded, Icons.manage_search_rounded, () => const SearchScreen(embedded: true)),
  _Dest('notebooks', Icons.menu_book_outlined, Icons.menu_book_rounded, () => const NotebooksScreen()),
  _Dest('voice_notes', Icons.mic_none_rounded, Icons.mic_rounded, () => const VoiceScreen()),
  _Dest('journal', Icons.auto_stories_outlined, Icons.auto_stories_rounded, () => const JournalScreen()),
  _Dest('calendar', Icons.calendar_month_outlined, Icons.calendar_month_rounded, () => const CalendarScreen()),
  _Dest('templates', Icons.dashboard_customize_outlined, Icons.dashboard_customize_rounded, () => const TemplatesScreen()),
  _Dest('tags', Icons.sell_outlined, Icons.sell_rounded, () => const TagsScreen()),
  _Dest('shared', Icons.people_outline_rounded, Icons.people_alt_rounded, () => const SharedScreen()),
  _Dest('settings', Icons.settings_outlined, Icons.settings_rounded, () => const SettingsScreen()),
];

const _mobileKeys = ['home', 'notes', 'search', 'notebooks'];

/// Bottom navigation on phones, a side rail on tablets and desktop.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  String _current = 'home';

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final wide = MediaQuery.of(context).size.width >= 840;
    final dest = _all.firstWhere((d) => d.key == _current);
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      child: KeyedSubtree(key: ValueKey(_current), child: dest.page()),
    );
    if (wide) {
      final i = _all.indexOf(dest);
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.vertical),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      extended: MediaQuery.of(context).size.width >= 1200,
                      minExtendedWidth: 210,
                      selectedIndex: i,
                      labelType: MediaQuery.of(context).size.width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: FloatingActionButton(
                          key: const Key('rail_new'),
                          heroTag: null,
                          elevation: 0,
                          tooltip: l.tr('new_note'),
                          onPressed: () => _newNote(),
                          child: const Icon(Icons.edit_rounded),
                        ),
                      ),
                      onDestinationSelected: (j) => setState(() => _current = _all[j].key),
                      destinations: [
                        for (final d in _all) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(l.tr(d.key))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    final mi = _mobileKeys.indexOf(_current);
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: mi < 0 ? 4 : mi,
        onDestinationSelected: (j) {
          if (j == 4) {
            _more();
            return;
          }
          setState(() => _current = _mobileKeys[j]);
        },
        destinations: [
          for (final k in _mobileKeys)
            NavigationDestination(icon: Icon(_all.firstWhere((d) => d.key == k).icon), selectedIcon: Icon(_all.firstWhere((d) => d.key == k).selected), label: l.tr(k)),
          NavigationDestination(key: const Key('nav_more'), icon: const Icon(Icons.apps_rounded), label: l.tr('more')),
        ],
      ),
    );
  }

  Future<void> _newNote() async {
    final repo = ref.read(repoProvider);
    if (repo == null) return;
    final id = await repo.createNote();
    if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
  }

  Future<void> _more() async {
    final l = context.l;
    final extra = <(String, IconData, Color, VoidCallback)>[
      for (final d in _all.where((d) => !_mobileKeys.contains(d.key)))
        (l.tr(d.key), d.selected, AppColors.primary, () => setState(() => _current = d.key)),
      (l.tr('favorites'), Icons.star_rounded, AppColors.warning, () => _push(const NotesListScreen(filter: NoteFilter('favorites')))),
      (l.tr('archive'), Icons.archive_rounded, AppColors.teal, () => _push(const NotesListScreen(filter: NoteFilter('archived')))),
      (l.tr('trash'), Icons.delete_rounded, AppColors.danger, () => _push(const NotesListScreen(filter: NoteFilter('trash')))),
      (l.tr('import_file'), Icons.file_open_rounded, AppColors.info, _import),
    ];
    final pick = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            for (var i = 0; i < extra.length; i++)
              InkWell(
                key: Key('more_$i'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.pop(ctx, i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(extra[i].$2, color: extra[i].$3, size: 28),
                    const SizedBox(height: 6),
                    Text(extra[i].$1, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11.5)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (pick != null) extra[pick].$4();
  }

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  /// Import TXT / Markdown / HTML files as notes.
  Future<void> _import() async {
    final files = ref.read(fileServiceProvider);
    final ex = ref.read(exportServiceProvider);
    if (files == null || ex == null) return;
    await guard(context, () async {
      final f = await files.pick(PickKind.importable);
      if (f == null) return;
      final id = await ex.importFile(f.name, await f.readAsBytes());
      if (mounted) {
        toast(context, context.tr('imported'));
        await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
      }
    });
  }
}

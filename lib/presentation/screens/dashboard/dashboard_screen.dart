import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/text_tools.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/notes_data.dart';
import '../../../domain/services/reminders.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../editor/note_editor_screen.dart';
import '../notebooks/notebooks_screen.dart';
import '../notes/note_actions.dart';
import '../notes/notes_list_screen.dart';
import '../search/search_screen.dart';
import '../tags/tags_screen.dart';
import '../voice/voice_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tr('app_name')),
        actions: [
          IconButton(key: const Key('dash_search'), tooltip: l.tr('search'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())), icon: const Icon(Icons.search_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('quick_create'),
        onPressed: () => showQuickCreate(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.tr('quick_create')),
      ),
      body: NotesView(
        builder: (context, ref, d) {
          final st = DashboardStats.of(d);
          final due = dueNow(d, DateTime.now());
          void open(NoteFilter f) => Navigator.push(context, MaterialPageRoute(builder: (_) => NotesListScreen(filter: f)));
          return PageList(
            onRefresh: () async => ref.read(revisionProvider.notifier).bump(),
            children: [
              Text(_greeting(l, session?.email), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(l.date(DateTime.now()), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              _QuickRow(),
              const SizedBox(height: 14),
              StatGrid(
                children: [
                  StatTile(key: const Key('stat_total'), icon: Icons.notes_rounded, label: l.tr('total_notes'), value: '${st.total}', color: AppColors.primary, onTap: () => open(NoteFilter.all)),
                  StatTile(icon: Icons.push_pin_rounded, label: l.tr('pinned'), value: '${st.pinned}', color: AppColors.amber, onTap: () => open(const NoteFilter('pinned'))),
                  StatTile(icon: Icons.star_rounded, label: l.tr('favorites'), value: '${st.favorites}', color: AppColors.warning, onTap: () => open(const NoteFilter('favorites'))),
                  StatTile(icon: Icons.menu_book_rounded, label: l.tr('notebooks_folders'), value: '${st.notebooks}', color: AppColors.teal, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotebooksScreen()))),
                  StatTile(icon: Icons.sell_rounded, label: l.tr('tags'), value: '${st.tags}', color: AppColors.purple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagsScreen()))),
                  StatTile(icon: Icons.delete_outline_rounded, label: l.tr('trash'), value: '${st.trashed}', color: AppColors.danger, onTap: () => open(const NoteFilter('trash'))),
                  StatTile(icon: Icons.graphic_eq_rounded, label: l.tr('voice_notes'), value: '${st.voices}', color: AppColors.pink, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceScreen()))),
                  StatTile(icon: Icons.sd_storage_rounded, label: l.tr('storage_used'), value: fileSize(st.storageBytes), color: AppColors.info),
                ],
              ),
              if (due.isNotEmpty) ...[
                SectionTitle(l.tr('due_now')),
                for (final n in due.take(5)) _noteTile(context, d, n, icon: Icons.alarm_on_rounded),
              ],
              if (d.pinned.isNotEmpty) ...[
                SectionTitle(l.tr('pinned_notes'), trailing: TextButton(onPressed: () => open(const NoteFilter('pinned')), child: Text(l.tr('see_all')))),
                _horizontal(context, d, d.pinned.take(10).toList()),
              ],
              if (d.favorites.isNotEmpty) ...[
                SectionTitle(l.tr('favorite_notes'), trailing: TextButton(onPressed: () => open(const NoteFilter('favorites')), child: Text(l.tr('see_all')))),
                _horizontal(context, d, d.favorites.take(10).toList()),
              ],
              SectionTitle(l.tr('recent_notes'), trailing: TextButton(onPressed: () => open(const NoteFilter('recent')), child: Text(l.tr('see_all')))),
              if (d.active.isEmpty)
                EmptyState(icon: Icons.edit_note_rounded, title: l.tr('welcome_title'), subtitle: l.tr('welcome_sub'))
              else ...[
                for (final n in d.recentlyCreated.take(3)) _noteTile(context, d, n, icon: Icons.fiber_new_rounded),
                SectionTitle(l.tr('recently_edited')),
                for (final n in d.recent.take(5)) _noteTile(context, d, n),
              ],
              if (d.upcoming(DateTime.now()).isNotEmpty) ...[
                SectionTitle(l.tr('upcoming')),
                for (final (n, t) in d.upcoming(DateTime.now()).take(4))
                  InfoTile(
                    icon: Icons.event_rounded,
                    color: AppColors.info,
                    title: n.displayTitle(l.tr('untitled')),
                    subtitle: l.dateTime(t),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id))),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _greeting(L10n l, String? email) {
    final h = DateTime.now().hour;
    return l.tr(h < 12 ? 'good_morning' : (h < 18 ? 'good_afternoon' : 'good_evening'));
  }

  Widget _noteTile(BuildContext context, NotesData d, Note n, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: NoteCard(note: n, data: d, compact: true, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id)))),
  );

  Widget _horizontal(BuildContext context, NotesData d, List<Note> notes) => SizedBox(
    height: 150,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: notes.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => SizedBox(
        width: 240,
        child: NoteCard(note: notes[i], data: d, compact: true, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: notes[i].id)))),
      ),
    ),
  );
}

class _QuickRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    Widget b(String k, IconData i, Color c, VoidCallback f) => Expanded(
      child: InkWell(
        key: Key('dash_$k'),
        borderRadius: BorderRadius.circular(16),
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Icon(i, color: c),
              const SizedBox(height: 4),
              Text(l.tr('quick_$k'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        b('note', Icons.note_add_rounded, AppColors.primary, () => createAndOpen(context, ref)),
        const SizedBox(width: 8),
        b('todo', Icons.checklist_rounded, AppColors.teal, () => createAndOpen(context, ref, type: 'todo')),
        const SizedBox(width: 8),
        b('voice', Icons.mic_rounded, AppColors.danger, () => showRecorderSheet(context, ref)),
        const SizedBox(width: 8),
        b('image', Icons.add_photo_alternate_rounded, AppColors.pink, () => createImageNote(context, ref)),
        const SizedBox(width: 8),
        b('document', Icons.description_rounded, AppColors.info, () => showQuickCreate(context, ref)),
      ],
    );
  }
}

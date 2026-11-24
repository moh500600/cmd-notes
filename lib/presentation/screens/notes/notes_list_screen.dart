import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/notes_data.dart';
import '../../../domain/services/trash.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../editor/note_editor_screen.dart';
import 'note_actions.dart';

/// Which notes a list shows.
class NoteFilter {
  final String kind; // all | favorites | pinned | archived | trash | notebook | tag | type | recent
  final String? id; // notebook / tag id or type key
  const NoteFilter(this.kind, [this.id]);

  static const all = NoteFilter('all');
}

List<Note> applyFilter(NotesData d, NoteFilter f, {String sort = 'updated'}) => switch (f.kind) {
  'favorites' => d.favorites,
  'pinned' => d.pinned,
  'archived' => sortNotes(d.archived, by: sort),
  'trash' => d.trash,
  'notebook' => d.inNotebook(f.id!, deep: false),
  'tag' => sortNotes(d.active.where((n) => d.tagsOfNote[n.id]?.contains(f.id) ?? false), by: sort),
  'type' => sortNotes(d.active.where((n) => n.type == f.id), by: sort),
  'recent' => d.recent.take(50).toList(),
  _ => sortNotes(d.active, by: sort),
};

String filterTitle(L10n l, NotesData d, NoteFilter f) => switch (f.kind) {
  'favorites' => l.tr('favorites'),
  'pinned' => l.tr('pinned'),
  'archived' => l.tr('archive'),
  'trash' => l.tr('trash'),
  'notebook' => d.tree.byId[f.id]?.name ?? l.tr('notebook'),
  'tag' => '#${d.tagById[f.id]?.name ?? ''}',
  'type' => typeLabel(l, f.id ?? 'text'),
  'recent' => l.tr('recently_edited'),
  _ => l.tr('all_notes'),
};

class NotesListScreen extends ConsumerStatefulWidget {
  final NoteFilter filter;
  final bool embedded; // inside the shell (no back button)
  const NotesListScreen({super.key, this.filter = NoteFilter.all, this.embedded = false});
  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  late NoteFilter _f = widget.filter;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    final d = ref.watch(notesProvider).value;
    final title = d == null ? l.tr('notes') : filterTitle(l, d, _f);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_f.kind == 'trash' && (d?.trash.isNotEmpty ?? false))
            TextButton(
              key: const Key('empty_trash'),
              onPressed: () async {
                if (!await confirm(context, l.tr('empty_trash_confirm'), okLabel: l.tr('empty_trash'))) return;
                final repo = ref.read(repoProvider)!;
                final files = ref.read(fileServiceProvider);
                for (final n in d!.trash) {
                  for (final a in d.attachmentsOf(n.id)) {
                    await files?.remove(a);
                  }
                  await repo.deleteForever(n.id);
                }
                if (context.mounted) toast(context, l.tr('trash_emptied'));
              },
              child: Text(l.tr('empty_trash')),
            ),
          IconButton(
            tooltip: l.tr(s.gridView ? 'list_view' : 'grid_view'),
            onPressed: () => ref.read(settingsProvider.notifier).update(s.copyWith(gridView: !s.gridView)),
            icon: Icon(s.gridView ? Icons.view_agenda_rounded : Icons.grid_view_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: l.tr('sort'),
            icon: const Icon(Icons.sort_rounded),
            onSelected: (v) => ref.read(settingsProvider.notifier).update(s.copyWith(noteSort: v)),
            itemBuilder: (_) => [
              for (final k in ['updated', 'created', 'title']) CheckedPopupMenuItem(value: k, checked: s.noteSort == k, child: Text(l.tr('sort_$k'))),
            ],
          ),
        ],
      ),
      floatingActionButton: _f.kind == 'trash' || _f.kind == 'archived'
          ? null
          : FloatingActionButton(
              key: const Key('new_note_fab'),
              tooltip: l.tr('new_note'),
              onPressed: () => showQuickCreate(context, ref, notebookId: _f.kind == 'notebook' ? _f.id : null),
              child: const Icon(Icons.add_rounded),
            ),
      body: NotesView(
        builder: (context, ref, d) {
          final list = applyFilter(d, _f, sort: s.noteSort);
          return Column(
            children: [
              if (widget.embedded) _filterChips(l, d),
              if (_f.kind == 'trash' && list.isNotEmpty)
                NoticeCard(l.tr('trash_hint', {'n': '${TrashPolicy.retentionDays}'}), color: AppColors.info),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: _f.kind == 'trash' ? Icons.delete_outline_rounded : Icons.note_alt_outlined,
                        title: l.tr(_f.kind == 'trash' ? 'trash_empty' : 'no_notes'),
                        subtitle: _f.kind == 'trash' ? null : l.tr('no_notes_sub'),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: s.gridView
                            ? GridView.builder(
                                key: const ValueKey('grid'),
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320, mainAxisExtent: 168, crossAxisSpacing: 8, mainAxisSpacing: 8),
                                itemCount: list.length,
                                itemBuilder: (_, i) => _card(d, list[i], compact: true),
                              )
                            : ListView.separated(
                                key: const ValueKey('list'),
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                                itemCount: list.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (_, i) => _card(d, list[i]),
                              ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(NotesData d, Note n, {bool compact = false}) {
    final l = context.l;
    return NoteCard(
      key: ValueKey(n.id),
      note: n,
      data: d,
      compact: compact,
      trailing: n.trashed ? Text(l.tr('days_left', {'n': '${TrashPolicy.daysLeft(n, DateTime.now())}'}), style: const TextStyle(fontSize: 11)) : null,
      onTap: () => n.trashed ? noteQuickActions(context, ref, n) : Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id))),
      onLongPress: () => noteQuickActions(context, ref, n),
    );
  }

  Widget _filterChips(L10n l, NotesData d) {
    final chips = <(NoteFilter, String)>[
      (NoteFilter.all, l.tr('all')),
      (const NoteFilter('favorites'), l.tr('favorites')),
      (const NoteFilter('pinned'), l.tr('pinned')),
      for (final t in d.tags) (NoteFilter('tag', t.id), '#${t.name} (${d.tagCount(t.id)})'),
      for (final t in kNoteTypes.where((t) => d.active.any((n) => n.type == t))) (NoteFilter('type', t), typeLabel(l, t)),
      (const NoteFilter('archived'), l.tr('archive')),
      (const NoteFilter('trash'), l.tr('trash')),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (f, label) in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(label: Text(label), selected: f.kind == _f.kind && f.id == _f.id, onSelected: (_) => setState(() => _f = f)),
            ),
        ],
      ),
    );
  }
}

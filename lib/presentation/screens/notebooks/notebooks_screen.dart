import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/folder_tree.dart';
import '../../../domain/services/notes_data.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../editor/note_editor_screen.dart';
import '../notes/note_actions.dart';
import '../sharing/share_sheet.dart';

/// Notebooks with unlimited nested folders.
class NotebooksScreen extends ConsumerStatefulWidget {
  const NotebooksScreen({super.key});
  @override
  ConsumerState<NotebooksScreen> createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends ConsumerState<NotebooksScreen> {
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('notebooks'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_notebook'),
        onPressed: () => editNotebook(context, ref),
        icon: const Icon(Icons.create_new_folder_rounded),
        label: Text(l.tr('new_notebook')),
      ),
      body: NotesView(
        builder: (context, ref, d) {
          final nodes = d.tree.build();
          if (nodes.isEmpty) {
            return EmptyState(icon: Icons.menu_book_rounded, title: l.tr('no_notebooks'), subtitle: l.tr('no_notebooks_sub'));
          }
          final pinned = nodes.where((n) => n.notebook.pinned).toList();
          final rest = nodes.where((n) => !n.notebook.pinned).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              for (final n in [...pinned, ...rest]) ..._node(d, n),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _node(NotesData d, FolderNode node) {
    final nb = node.notebook;
    final open = _open.contains(nb.id);
    final count = d.notebookCount(nb.id);
    final color = AppColors.parse(nb.color);
    return [
      Padding(
        padding: EdgeInsetsDirectional.only(start: node.depth * 22.0, bottom: 4),
        child: Card(
          child: ListTile(
            key: Key('nb_${nb.name}'),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  child: node.children.isEmpty
                      ? null
                      : IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          onPressed: () => setState(() => open ? _open.remove(nb.id) : _open.add(nb.id)),
                          icon: AnimatedRotation(turns: open ? 0.25 : 0, duration: const Duration(milliseconds: 180), child: Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded)),
                        ),
                ),
                Icon(node.depth == 0 ? notebookIcon(nb.icon) : Icons.folder_rounded, color: color),
              ],
            ),
            title: Text(nb.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([context.tr('n_notes', {'n': '$count'}), if (node.children.isNotEmpty) context.tr('n_folders', {'n': '${node.children.length}'}), if (nb.description.isNotEmpty) nb.description].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (nb.pinned) const Icon(Icons.push_pin_rounded, size: 16, color: AppColors.amber),
                PopupMenuButton<String>(onSelected: (v) => _action(d, nb, v), itemBuilder: (_) => _menu(nb)),
              ],
            ),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotebookScreen(notebookId: nb.id))),
          ),
        ),
      ),
      if (open) for (final c in node.children) ..._node(d, c),
    ];
  }

  List<PopupMenuEntry<String>> _menu(Notebook nb) {
    final l = context.l;
    PopupMenuItem<String> i(String v, IconData ic, String t) => PopupMenuItem(value: v, child: Row(children: [Icon(ic, size: 20), const SizedBox(width: 10), Text(t)]));
    return [
      i('sub', Icons.create_new_folder_outlined, l.tr('new_subfolder')),
      i('edit', Icons.edit_rounded, l.tr('edit')),
      i('pin', Icons.push_pin_rounded, l.tr(nb.pinned ? 'unpin' : 'pin')),
      i('move', Icons.drive_file_move_rounded, l.tr('move')),
      i('up', Icons.arrow_upward_rounded, l.tr('move_up')),
      i('down', Icons.arrow_downward_rounded, l.tr('move_down')),
      i('share', Icons.share_rounded, l.tr('share_collaborate')),
      i('delete', Icons.delete_outline_rounded, l.tr('delete')),
    ];
  }

  Future<void> _action(NotesData d, Notebook nb, String v) async {
    final repo = ref.read(repoProvider)!;
    final l = context.l;
    switch (v) {
      case 'sub':
        await editNotebook(context, ref, parentId: nb.id);
        setState(() => _open.add(nb.id));
      case 'edit':
        await editNotebook(context, ref, existing: nb);
      case 'pin':
        await repo.saveNotebook(id: nb.id, name: nb.name, pinned: !nb.pinned);
      case 'move':
        final to = await pickNotebook(context, d, current: nb.parentId, excludeTree: nb.id);
        if (to != null && mounted) await guard(context, () => repo.moveNotebook(nb.id, to.isEmpty ? null : to));
      case 'up' || 'down':
        final sibs = [...d.tree.childrenOf(nb.parentId)];
        final i = sibs.indexWhere((s) => s.id == nb.id);
        final j = v == 'up' ? i - 1 : i + 1;
        if (i < 0 || j < 0 || j >= sibs.length) return;
        sibs.insert(j, sibs.removeAt(i));
        await repo.reorderNotebooks(sibs);
      case 'share':
        await showShareSheet(context, ref, notebookId: nb.id, title: nb.name);
      case 'delete':
        if (await confirm(context, l.tr('delete_notebook_confirm', {'name': nb.name}))) await repo.deleteNotebook(nb.id);
    }
  }
}

/// Create or edit a notebook / folder (name, colour, icon, description).
Future<String?> editNotebook(BuildContext context, WidgetRef ref, {Notebook? existing, String? parentId}) async {
  final repo = ref.read(repoProvider);
  if (repo == null) return null;
  final l = context.l;
  final name = TextEditingController(text: existing?.name ?? '');
  final desc = TextEditingController(text: existing?.description ?? '');
  var color = existing?.color ?? AppColors.swatches.first;
  var icon = existing?.icon.isNotEmpty == true ? existing!.icon : 'book';
  final isSub = (existing?.parentId ?? parentId) != null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(l.tr(existing != null ? 'edit_notebook' : (isSub ? 'new_subfolder' : 'new_notebook'))),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(key: const Key('nb_name'), controller: name, autofocus: true, decoration: InputDecoration(labelText: l.tr('name'))),
                const SizedBox(height: 8),
                TextField(controller: desc, decoration: InputDecoration(labelText: l.tr('description'))),
                const SizedBox(height: 14),
                Text(l.tr('color'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ColorPicker(value: color, onChanged: (c) => setS(() => color = c)),
                const SizedBox(height: 14),
                Text(l.tr('icon'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                IconPicker(value: icon, color: AppColors.parse(color), onChanged: (i) => setS(() => icon = i)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.tr('cancel'))),
          FilledButton(key: const Key('nb_save'), onPressed: () => Navigator.pop(ctx, true), child: Text(l.tr('save'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  String? id;
  await guard(context, () async {
    id = await repo.saveNotebook(id: existing?.id, parentId: parentId, name: name.text, color: color, icon: icon, description: desc.text.trim());
  });
  return id;
}

/// One notebook: its sub-folders and its notes.
class NotebookScreen extends ConsumerWidget {
  final String notebookId;
  const NotebookScreen({super.key, required this.notebookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return NotesView(
      builder: (context, ref, d) {
        final nb = d.tree.byId[notebookId];
        if (nb == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(l.tr('err_not_found'))));
        final subs = d.tree.childrenOf(nb.id);
        final notes = d.inNotebook(nb.id, deep: false);
        final color = AppColors.parse(nb.color);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nb.name),
                if (nb.parentId != null) Text(d.tree.path(nb.parentId), style: const TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              IconButton(tooltip: l.tr('new_subfolder'), onPressed: () => editNotebook(context, ref, parentId: nb.id), icon: const Icon(Icons.create_new_folder_outlined)),
              IconButton(tooltip: l.tr('share_collaborate'), onPressed: () => showShareSheet(context, ref, notebookId: nb.id, title: nb.name), icon: const Icon(Icons.share_rounded)),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            key: const Key('nb_new_note'),
            onPressed: () => showQuickCreate(context, ref, notebookId: nb.id),
            child: const Icon(Icons.add_rounded),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              if (subs.isNotEmpty) ...[
                SectionTitle(l.tr('folders')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in subs)
                      ActionChip(
                        avatar: Icon(Icons.folder_rounded, color: AppColors.parse(s.color)),
                        label: Text('${s.name} (${d.inNotebook(s.id).length})'),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotebookScreen(notebookId: s.id))),
                      ),
                  ],
                ),
              ],
              SectionTitle(l.tr('notes'), icon: notebookIcon(nb.icon)),
              if (notes.isEmpty) EmptyState(icon: Icons.note_alt_outlined, title: l.tr('no_notes'), subtitle: l.tr('no_notes_sub')),
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NoteCard(
                    note: n,
                    data: d,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id))),
                    onLongPress: () => noteQuickActions(context, ref, n),
                  ),
                ),
              if (d.voices.any((v) => v.notebookId == nb.id)) ...[
                SectionTitle(l.tr('voice_notes')),
                for (final v in d.voices.where((v) => v.notebookId == nb.id))
                  InfoTile(icon: Icons.graphic_eq_rounded, color: color, title: v.title, subtitle: l.dateTime(v.createdAt)),
              ],
            ],
          ),
        );
      },
    );
  }
}

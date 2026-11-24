import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../notes/notes_list_screen.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('tags'))),
      floatingActionButton: FloatingActionButton(key: const Key('new_tag'), tooltip: l.tr('new_tag'), onPressed: () => editTag(context, ref), child: const Icon(Icons.add_rounded)),
      body: NotesView(
        builder: (context, ref, d) {
          if (d.tags.isEmpty) return EmptyState(icon: Icons.sell_outlined, title: l.tr('no_tags'), subtitle: l.tr('no_tags_sub'));
          final sorted = [...d.tags]..sort((a, b) => d.tagCount(b.id).compareTo(d.tagCount(a.id)));
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              for (final t in sorted)
                InfoTile(
                  icon: Icons.tag_rounded,
                  color: AppColors.parse(t.color),
                  title: t.name,
                  subtitle: l.tr('n_notes', {'n': '${d.tagCount(t.id)}'}),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotesListScreen(filter: NoteFilter('tag', t.id)))),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await editTag(context, ref, existing: t);
                      if (v == 'delete' && context.mounted && await confirm(context, l.tr('delete_tag_confirm', {'name': t.name}))) await ref.read(repoProvider)!.deleteTag(t.id);
                    },
                    itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(l.tr('edit'))), PopupMenuItem(value: 'delete', child: Text(l.tr('delete')))],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> editTag(BuildContext context, WidgetRef ref, {Tag? existing}) async {
  final l = context.l;
  final name = TextEditingController(text: existing?.name ?? '');
  var color = existing?.color ?? AppColors.swatches[3];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(l.tr(existing == null ? 'new_tag' : 'edit_tag')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(key: const Key('tag_name'), controller: name, autofocus: true, decoration: InputDecoration(labelText: l.tr('name'), prefixText: '#')),
            const SizedBox(height: 12),
            ColorPicker(value: color, onChanged: (c) => setS(() => color = c)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.tr('save'))),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) await guard(context, () => ref.read(repoProvider)!.saveTag(id: existing?.id, name: name.text, color: color));
}

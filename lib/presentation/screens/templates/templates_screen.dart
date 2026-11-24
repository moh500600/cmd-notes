import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/delta_doc.dart';
import '../../../domain/services/note_format.dart';
import '../../../domain/services/templates.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../notes/note_actions.dart';

/// The template library (11 built-in) plus the user's own templates, and the default per note type.
class TemplatesScreen extends ConsumerWidget {
  final String? notebookId;
  const TemplatesScreen({super.key, this.notebookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final ar = l.ar;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tr('templates')),
        actions: [IconButton(tooltip: l.tr('default_templates'), onPressed: () => _defaults(context, ref), icon: const Icon(Icons.tune_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_template'),
        onPressed: () => _editUserTemplate(context, ref),
        icon: const Icon(Icons.bookmark_add_rounded),
        label: Text(l.tr('new_template')),
      ),
      body: NotesView(
        builder: (context, ref, d) => PageList(
          children: [
            SectionTitle(l.tr('template_library'), icon: Icons.auto_awesome_mosaic_rounded),
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
                final w = (c.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in kTemplateLibrary)
                      SizedBox(
                        width: w,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: InkWell(
                            key: Key('tpl_${t.key}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => createAndOpen(context, ref, type: t.type, content: t.body(ar), title: t.name(ar), templateKey: t.key, notebookId: notebookId),
                            onLongPress: () => _preview(context, t.name(ar), t.body(ar)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(backgroundColor: AppColors.type(t.type).withValues(alpha: 0.14), child: Icon(templateIcon(t.icon), color: AppColors.type(t.type))),
                                  const SizedBox(height: 10),
                                  Text(t.name(ar), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(typeLabel(l, t.type), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            SectionTitle(l.tr('my_templates'), icon: Icons.bookmarks_rounded),
            if (d.templates.isEmpty) NoticeCard(l.tr('no_user_templates')),
            for (final t in d.templates)
              InfoTile(
                icon: templateIcon(t.icon),
                color: AppColors.type(t.type),
                title: t.name,
                subtitle: [typeLabel(l, t.type), if (t.description.isNotEmpty) t.description].join(' · '),
                onTap: () => createAndOpen(context, ref, type: t.type, content: t.content, notebookId: notebookId),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    final repo = ref.read(repoProvider)!;
                    if (v == 'preview') _preview(context, t.name, t.content);
                    if (v == 'edit') await _editUserTemplate(context, ref, existing: t);
                    if (v == 'delete' && context.mounted && await confirm(context, l.tr('delete_template_confirm'))) await repo.delete('templates', t.id);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'preview', child: Text(l.tr('preview'))),
                    PopupMenuItem(value: 'edit', child: Text(l.tr('edit'))),
                    PopupMenuItem(value: 'delete', child: Text(l.tr('delete'))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _preview(BuildContext context, String name, String body) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(name),
      content: SingleChildScrollView(child: Text(DeltaDoc.parse(body).plainText)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('close')))],
    ),
  );

  /// A user template: name, type, icon and body (plain lines; "- [ ]" lines become checkboxes, "# " headings).
  Future<void> _editUserTemplate(BuildContext context, WidgetRef ref, {NoteTemplate? existing}) async {
    final l = context.l;
    final name = TextEditingController(text: existing?.name ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final body = TextEditingController(text: existing == null ? '' : NoteFormat.toMarkdown('', DeltaDoc.parse(existing.content)).trim());
    var type = existing?.type ?? 'text';
    var icon = existing?.icon.isNotEmpty == true ? existing!.icon : 'description';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l.tr(existing == null ? 'new_template' : 'edit_template')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(key: const Key('tpl_name'), controller: name, decoration: InputDecoration(labelText: l.tr('name'))),
                  const SizedBox(height: 8),
                  TextField(controller: desc, decoration: InputDecoration(labelText: l.tr('description'))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(labelText: l.tr('note_type')),
                    items: [for (final t in kNoteTypes) DropdownMenuItem(value: t, child: Text(typeLabel(l, t)))],
                    onChanged: (v) => setS(() => type = v ?? 'text'),
                  ),
                  const SizedBox(height: 10),
                  IconPicker(value: icon, icons: kTemplateIcons, color: AppColors.type(type), onChanged: (i) => setS(() => icon = i)),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('tpl_body'),
                    controller: body,
                    minLines: 5,
                    maxLines: 12,
                    decoration: InputDecoration(labelText: l.tr('template_body'), helperText: l.tr('template_body_help'), helperMaxLines: 3, alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.tr('save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (name.text.trim().isEmpty) return toast(context, l.tr('err_name_required'));
    await guard(context, () async {
      await ref.read(repoProvider)!.saveTemplate(id: existing?.id, name: name.text.trim(), type: type, icon: icon, description: desc.text.trim(), content: NoteFormat.fromMarkdown(body.text, takeTitle: false).$2.toJson());
    });
  }

  /// Which template a new note of each type starts from.
  Future<void> _defaults(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final d = await ref.read(notesProvider.future);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(settingsProvider);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                Text(l.tr('default_templates'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(l.tr('default_templates_sub'), style: const TextStyle(fontSize: 12.5)),
                for (final t in kNoteTypes)
                  ListTile(
                    leading: Icon(typeIcon(t), color: AppColors.type(t)),
                    title: Text(typeLabel(l, t)),
                    trailing: DropdownButton<String>(
                      value: s.typeTemplates[t] ?? '',
                      items: [
                        DropdownMenuItem(value: '', child: Text(l.tr('builtin'))),
                        for (final u in d.templates) DropdownMenuItem(value: u.id, child: Text(u.name)),
                      ],
                      onChanged: (v) {
                        final m = {...s.typeTemplates};
                        if (v == null || v.isEmpty) {
                          m.remove(t);
                        } else {
                          m[t] = v;
                        }
                        ref.read(settingsProvider.notifier).update(s.copyWith(typeTemplates: m));
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/file_service.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/delta_doc.dart';
import '../../../domain/services/templates.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../editor/note_editor_screen.dart';
import '../templates/templates_screen.dart';
import '../voice/voice_screen.dart';

/// Creates a note of [type] (body from the user's template for that type, else the built-in one) and opens it.
Future<String?> createAndOpen(BuildContext context, WidgetRef ref, {String type = 'text', String? notebookId, String? content, String title = '', String templateKey = '', DateTime? eventAt}) async {
  final repo = ref.read(repoProvider);
  if (repo == null) return null;
  final s = ref.read(settingsProvider);
  var body = content;
  if (body == null) {
    final userTpl = s.typeTemplates[type];
    if (userTpl != null) {
      final d = await ref.read(notesProvider.future);
      body = d.templates.where((t) => t.id == userTpl).firstOrNull?.content;
    }
    body ??= defaultBodyFor(type, s.lang == 'ar');
  }
  final id = await repo.createNote(type: type, notebookId: notebookId, title: title, content: body, templateKey: templateKey, eventAt: eventAt);
  if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
  return id;
}

/// A photo note: pick/take a picture, then a note with the image.
Future<void> createImageNote(BuildContext context, WidgetRef ref, {String? notebookId, bool camera = false}) async {
  final repo = ref.read(repoProvider);
  final files = ref.read(fileServiceProvider);
  if (repo == null || files == null) return;
  await guard(context, () async {
    String? name;
    List<int>? bytes;
    if (PlatformSupport.isMobile) {
      final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, imageQuality: 85, maxWidth: 2400);
      if (x == null) return;
      name = x.name;
      bytes = await x.readAsBytes();
    } else {
      final f = await files.pick(PickKind.image);
      if (f == null) return;
      name = f.name;
      bytes = await f.readAsBytes();
    }
    final id = await repo.createNote(type: 'personal', notebookId: notebookId, content: DeltaBuilder().json());
    final att = await files.addBytes(name, Uint8List.fromList(bytes), noteId: id);
    final doc = DeltaDoc.fromBlocks([
      Block(const [], const {}, embedType: Embeds.image, embedData: '{"id":"$att","name":"$name"}'),
      const Block([], {}),
    ]);
    await repo.saveContent(id, '', doc.toJson());
    if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
  });
}

/// The quick-create menu (spec §2): note, to-do list, voice, photo note, document (from a template).
Future<void> showQuickCreate(BuildContext context, WidgetRef ref, {String? notebookId}) async {
  final l = context.l;
  final v = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (k, icon, color) in [
              ('note', Icons.note_add_rounded, AppColors.primary),
              ('todo', Icons.checklist_rounded, AppColors.teal),
              ('voice', Icons.mic_rounded, AppColors.danger),
              ('image', Icons.add_photo_alternate_rounded, AppColors.pink),
              ('document', Icons.description_rounded, AppColors.info),
              ('journal', Icons.auto_stories_rounded, AppColors.amber),
            ])
              SizedBox(
                width: 100,
                child: InkWell(
                  key: Key('quick_$k'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(ctx, k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      children: [
                        CircleAvatar(radius: 26, backgroundColor: color.withValues(alpha: 0.14), child: Icon(icon, color: color)),
                        const SizedBox(height: 6),
                        Text(l.tr('quick_$k'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'note':
      await createAndOpen(context, ref, notebookId: notebookId);
    case 'todo':
      await createAndOpen(context, ref, type: 'todo', notebookId: notebookId);
    case 'voice':
      await showRecorderSheet(context, ref, notebookId: notebookId);
    case 'image':
      await createImageNote(context, ref, notebookId: notebookId);
    case 'document':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => TemplatesScreen(notebookId: notebookId)));
    case 'journal':
      await createAndOpen(context, ref, type: 'journal', notebookId: notebookId);
  }
}

/// Long-press actions on a note card.
Future<void> noteQuickActions(BuildContext context, WidgetRef ref, Note n) async {
  final repo = ref.read(repoProvider);
  if (repo == null) return;
  final l = context.l;
  final v = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          if (n.trashed) ...[
            ListTile(leading: const Icon(Icons.restore_from_trash_rounded), title: Text(l.tr('restore')), onTap: () => Navigator.pop(ctx, 'restore')),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              title: Text(l.tr('delete_forever'), style: const TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'forever'),
            ),
          ] else ...[
            ListTile(leading: Icon(n.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded), title: Text(l.tr(n.pinned ? 'unpin' : 'pin')), onTap: () => Navigator.pop(ctx, 'pin')),
            ListTile(leading: Icon(n.favorite ? Icons.star_border_rounded : Icons.star_rounded), title: Text(l.tr(n.favorite ? 'unfavorite' : 'favorite')), onTap: () => Navigator.pop(ctx, 'fav')),
            ListTile(leading: const Icon(Icons.drive_file_move_rounded), title: Text(l.tr('move_to_notebook')), onTap: () => Navigator.pop(ctx, 'move')),
            ListTile(leading: const Icon(Icons.sell_rounded), title: Text(l.tr('tags')), onTap: () => Navigator.pop(ctx, 'tags')),
            ListTile(leading: Icon(n.archived ? Icons.unarchive_rounded : Icons.archive_rounded), title: Text(l.tr(n.archived ? 'unarchive' : 'archive')), onTap: () => Navigator.pop(ctx, 'archive')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(l.tr('move_to_trash')), onTap: () => Navigator.pop(ctx, 'trash')),
          ],
        ],
      ),
    ),
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'restore':
      await repo.restore(n.id);
      if (context.mounted) toast(context, l.tr('restored'));
    case 'forever':
      await deleteForeverConfirmed(context, ref, n);
    case 'pin':
      await repo.setPinned(n.id, !n.pinned);
    case 'fav':
      await repo.setFavorite(n.id, !n.favorite);
    case 'move':
      final d = await ref.read(notesProvider.future);
      if (!context.mounted) return;
      final to = await pickNotebook(context, d, current: n.notebookId);
      if (to != null) await repo.move(n.id, to.isEmpty ? null : to);
    case 'tags':
      await editNoteTags(context, ref, n.id);
    case 'archive':
      await repo.archive(n.id, !n.archived);
    case 'trash':
      await repo.trash(n.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.tr('moved_to_trash')), action: SnackBarAction(label: l.tr('undo'), onPressed: () => repo.restore(n.id))),
        );
      }
  }
}

/// Permanent delete after the user confirms (files are removed from the device and the cloud).
Future<void> deleteForeverConfirmed(BuildContext context, WidgetRef ref, Note n) async {
  final l = context.l;
  if (!await confirm(context, l.tr('delete_forever_confirm'), okLabel: l.tr('delete_forever'))) return;
  final repo = ref.read(repoProvider)!;
  final files = ref.read(fileServiceProvider);
  final d = await ref.read(notesProvider.future);
  for (final a in d.attachmentsOf(n.id)) {
    await files?.remove(a);
  }
  await repo.deleteForever(n.id);
  if (context.mounted) toast(context, l.tr('deleted_forever'));
}

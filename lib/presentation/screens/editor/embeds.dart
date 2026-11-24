import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/text_tools.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/delta_doc.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Inserts a custom block embed at the cursor and moves the cursor after it.
void insertEmbed(QuillController c, String type, Object data) {
  final sel = c.selection;
  final idx = sel.isValid ? sel.start : c.document.length - 1;
  final len = sel.isValid ? sel.end - sel.start : 0;
  c.replaceText(idx, len, CustomBlockEmbed(type, data is String ? data : jsonEncode(data)), TextSelection.collapsed(offset: idx + 1));
}

Map<String, dynamic> _map(Embed node) {
  final d = node.value.data;
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is String && d.startsWith('{')) {
    try {
      return Map<String, dynamic>.from(jsonDecode(d) as Map);
    } catch (_) {}
  }
  return const {};
}

final _bytesCache = <String, Uint8List>{};

/// Bytes of an attachment (device copy or downloaded), cached for the session.
final attachmentBytesProvider = FutureProvider.family<Uint8List?, String>((ref, id) async {
  if (_bytesCache.containsKey(id)) return _bytesCache[id];
  final d = await ref.watch(notesProvider.future);
  final files = ref.read(fileServiceProvider);
  final a = d.attachments.where((a) => a.id == id).firstOrNull;
  if (a == null || files == null) return null;
  try {
    final b = await files.bytes(a);
    if (b.length < 12 * 1024 * 1024) _bytesCache[id] = b;
    return b;
  } catch (_) {
    return null;
  }
});

class ImageEmbedBuilder extends EmbedBuilder {
  const ImageEmbedBuilder();
  @override
  String get key => Embeds.image;
  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext ec) {
    final id = _map(ec.node)['id']?.toString() ?? '';
    return Consumer(
      builder: (context, ref, _) {
        final a = ref.watch(attachmentBytesProvider(id));
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: a.when(
              data: (b) => b == null
                  ? Container(height: 90, color: cs.surfaceContainer, alignment: Alignment.center, child: const Icon(Icons.broken_image_rounded))
                  : GestureDetector(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(b))),
                      ),
                      child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 420), child: Image.memory(b, fit: BoxFit.contain)),
                    ),
              loading: () => Container(height: 120, color: cs.surfaceContainer, alignment: Alignment.center, child: const CircularProgressIndicator()),
              error: (_, _) => Container(height: 90, color: cs.surfaceContainer, alignment: Alignment.center, child: const Icon(Icons.broken_image_rounded)),
            ),
          ),
        );
      },
    );
  }
}

class FileEmbedBuilder extends EmbedBuilder {
  const FileEmbedBuilder();
  @override
  String get key => Embeds.file;
  @override
  String toPlainText(Embed node) => _map(node)['name']?.toString() ?? '';

  @override
  Widget build(BuildContext context, EmbedContext ec) {
    final m = _map(ec.node);
    final id = m['id']?.toString() ?? '';
    final name = m['name']?.toString() ?? '';
    return Consumer(
      builder: (context, ref, _) {
        final d = ref.watch(notesProvider).value;
        final a = d?.attachments.where((a) => a.id == id).firstOrNull;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: Icon(attIcon(a?.fileType ?? ''), color: Theme.of(context).colorScheme.primary),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: a == null ? null : Text(fileSize(a.size)),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: a == null ? null : () => guard(context, () => ref.read(fileServiceProvider)!.open(a)),
          ),
        );
      },
    );
  }
}

IconData attIcon(String type) => switch (type) {
  'pdf' => Icons.picture_as_pdf_rounded,
  'image' => Icons.image_rounded,
  'word' => Icons.description_rounded,
  'excel' => Icons.table_chart_rounded,
  'powerpoint' => Icons.slideshow_rounded,
  'audio' => Icons.audiotrack_rounded,
  'text' => Icons.article_rounded,
  _ => Icons.attach_file_rounded,
};

class DividerEmbedBuilder extends EmbedBuilder {
  const DividerEmbedBuilder();
  @override
  String get key => Embeds.divider;
  @override
  String toPlainText(Embed node) => '\n';
  @override
  Widget build(BuildContext context, EmbedContext ec) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const Expanded(child: Divider(thickness: 1.2)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.more_horiz_rounded, color: Theme.of(context).colorScheme.outline)),
        const Expanded(child: Divider(thickness: 1.2)),
      ],
    ),
  );
}

/// A simple table embed: rows of text cells (first row = header). Tap to edit.
class TableEmbedBuilder extends EmbedBuilder {
  const TableEmbedBuilder();
  @override
  String get key => Embeds.table;
  @override
  String toPlainText(Embed node) => _rows(node).map((r) => r.join(' | ')).join('\n');

  static List<List<String>> _rows(Embed node) {
    final r = _map(node)['rows'];
    if (r is! List) {
      return [
        ['', ''],
        ['', ''],
      ];
    }
    return [
      for (final row in r)
        if (row is List) [for (final c in row) c?.toString() ?? ''],
    ];
  }

  @override
  Widget build(BuildContext context, EmbedContext ec) {
    final rows = _rows(ec.node);
    final cs = Theme.of(context).colorScheme;
    final width = rows.isEmpty ? 0 : rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final table = Table(
      border: TableBorder.all(color: cs.outlineVariant),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        for (var i = 0; i < rows.length; i++)
          TableRow(
            decoration: i == 0 ? BoxDecoration(color: cs.primary.withValues(alpha: 0.08)) : null,
            children: [
              for (var j = 0; j < width; j++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60, maxWidth: 240),
                    child: Text(j < rows[i].length ? rows[i][j] : '', style: TextStyle(fontWeight: i == 0 ? FontWeight.w700 : null)),
                  ),
                ),
            ],
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: ec.readOnly
            ? null
            : () async {
                final out = await editTable(context, rows);
                if (out == null) return;
                final offset = ec.node.documentOffset;
                if (out.isEmpty) {
                  ec.controller.replaceText(offset, 1, '', TextSelection.collapsed(offset: offset));
                } else {
                  ec.controller.replaceText(offset, 1, CustomBlockEmbed(Embeds.table, jsonEncode({'rows': out})), null);
                }
              },
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: table),
      ),
    );
  }
}

/// The table editor: edit cells, add/remove rows and columns. Returns [] to delete the table.
Future<List<List<String>>?> editTable(BuildContext context, List<List<String>> initial) {
  return showDialog<List<List<String>>>(context: context, builder: (_) => _TableDialog(initial));
}

class _TableDialog extends StatefulWidget {
  final List<List<String>> initial;
  const _TableDialog(this.initial);
  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late List<List<TextEditingController>> _c;

  @override
  void initState() {
    super.initState();
    final w = widget.initial.isEmpty ? 2 : widget.initial.map((r) => r.length).reduce((a, b) => a > b ? a : b).clamp(1, 12);
    _c = [
      for (final r in (widget.initial.isEmpty ? [List.filled(w, ''), List.filled(w, '')] : widget.initial))
        [for (var j = 0; j < w; j++) TextEditingController(text: j < r.length ? r[j] : '')],
    ];
  }

  @override
  void dispose() {
    for (final r in _c) {
      for (final c in r) {
        c.dispose();
      }
    }
    super.dispose();
  }

  int get _w => _c.first.length;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AlertDialog(
      title: Text(l.tr('edit_table')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _c.length; i++)
                  Row(
                    children: [
                      for (var j = 0; j < _w; j++)
                        Padding(
                          padding: const EdgeInsets.all(3),
                          child: SizedBox(
                            width: 130,
                            child: TextField(
                              controller: _c[i][j],
                              style: TextStyle(fontWeight: i == 0 ? FontWeight.w700 : null, fontSize: 14),
                              decoration: InputDecoration(isDense: true, hintText: i == 0 ? l.tr('header_cell') : null),
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: l.tr('remove_row'),
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                        onPressed: _c.length <= 1 ? null : () => setState(() => _c.removeAt(i)),
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _c.add([for (var j = 0; j < _w; j++) TextEditingController()])),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l.tr('add_row')),
                    ),
                    TextButton.icon(
                      onPressed: _w >= 12 ? null : () => setState(() => [for (final r in _c) r.add(TextEditingController())]),
                      icon: const Icon(Icons.view_column_rounded),
                      label: Text(l.tr('add_column')),
                    ),
                    TextButton.icon(
                      onPressed: _w <= 1 ? null : () => setState(() => [for (final r in _c) r.removeLast()]),
                      icon: const Icon(Icons.remove_rounded),
                      label: Text(l.tr('remove_column')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, <List<String>>[]), child: Text(l.tr('delete_table'), style: const TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, [for (final r in _c) [for (final c in r) c.text]]), child: Text(l.tr('save'))),
      ],
    );
  }
}

const kEmbedBuilders = <EmbedBuilder>[ImageEmbedBuilder(), FileEmbedBuilder(), DividerEmbedBuilder(), TableEmbedBuilder()];

/// Renders unknown embeds (from a newer version) as a small placeholder instead of crashing.
class UnknownEmbedBuilder extends EmbedBuilder {
  const UnknownEmbedBuilder();
  @override
  String get key => 'unknown';
  @override
  Widget build(BuildContext context, EmbedContext ec) => const Icon(Icons.extension_rounded);
}

/// The note's attachment rows referenced by image/file embeds — used to clean up after deletes.
Set<String> referencedAttachmentIds(String deltaJson) => DeltaDoc.parse(deltaJson).attachmentIds;

extension AttachmentX on Attachment {
  bool get isImage => fileType == 'image';
}

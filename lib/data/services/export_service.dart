import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/errors/app_exception.dart';
import '../../core/utils/text_tools.dart';
import '../../core/utils/time.dart';
import '../../domain/services/delta_doc.dart';
import '../../domain/services/note_format.dart';
import '../repositories/notes_repository.dart';
import '../security/field_cipher.dart';

enum ExportFormat { pdf, docx, txt, md, html }

extension ExportFormatX on ExportFormat {
  String get ext => switch (this) {
    ExportFormat.pdf => 'pdf',
    ExportFormat.docx => 'docx',
    ExportFormat.txt => 'txt',
    ExportFormat.md => 'md',
    ExportFormat.html => 'html',
  };
}

/// Loads the PDF fonts (the app bundles Tajawal, which covers Arabic and Latin).
typedef FontLoader = Future<ByteData> Function(String asset);

/// Export of notes (PDF / DOCX / TXT / Markdown / HTML), import (TXT / Markdown / HTML)
/// and backup / restore (JSON, optionally password-encrypted).
class ExportService {
  final NotesRepository repo;
  final FontLoader loadFont;
  ExportService(this.repo, this.loadFont);

  static const format = 'notes_pro_backup';

  static Future<Directory> outDir() async {
    final d = Directory(p.join((await getTemporaryDirectory()).path, 'notes_exports'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String safeFileName(String title, String fallback) {
    final t = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_');
    final s = t.isEmpty ? fallback : t;
    return s.runes.length > 60 ? String.fromCharCodes(s.runes.take(60)) : s;
  }

  /// One note as bytes in [fmt].
  Future<List<int>> noteBytes(String title, DeltaDoc doc, ExportFormat fmt, {bool rtlUi = true}) async => switch (fmt) {
    ExportFormat.txt => utf8.encode(NoteFormat.toTxt(title, doc)),
    ExportFormat.md => utf8.encode(NoteFormat.toMarkdown(title, doc)),
    ExportFormat.html => utf8.encode(NoteFormat.toHtml(title, doc, rtl: isRtlText('$title ${doc.plainText}') || (rtlUi && doc.plainText.trim().isEmpty))),
    ExportFormat.docx => NoteFormat.toDocx(title, doc),
    ExportFormat.pdf => await pdf([(title, doc)], rtlUi: rtlUi),
  };

  Future<File> exportNote(String title, DeltaDoc doc, ExportFormat fmt, {bool rtlUi = true, String fallbackName = 'note'}) async {
    final f = File(p.join((await outDir()).path, '${safeFileName(title, fallbackName)}.${fmt.ext}'));
    await f.writeAsBytes(await noteBytes(title, doc, fmt, rtlUi: rtlUi), flush: true);
    return f;
  }

  Future<File> writeOut(String name, List<int> bytes) async {
    final f = File(p.join((await outDir()).path, name));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static pw.Font? _regular, _bold;

  /// A PDF of one or more notes. Each paragraph takes its own direction (Arabic right-to-left,
  /// English left-to-right); table columns are mirrored for Arabic so the first column is on the right.
  Future<Uint8List> pdf(List<(String, DeltaDoc)> notes, {bool rtlUi = true}) async {
    _regular ??= pw.Font.ttf(await loadFont('assets/fonts/Tajawal-Regular.ttf'));
    _bold ??= pw.Font.ttf(await loadFont('assets/fonts/Tajawal-Bold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: _regular, bold: _bold), title: notes.length == 1 ? notes.first.$1 : 'CMD Notes', author: 'CMD Notes');
    for (final (title, d) in notes) {
      final body = <pw.Widget>[];
      final docRtl = isRtlText('$title ${d.plainText}') || (rtlUi && '$title${d.plainText}'.trim().isEmpty);
      pw.TextDirection dirOf(String s) => s.trim().isEmpty ? (docRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr) : (isRtlText(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr);
      if (title.trim().isNotEmpty) {
        body.add(pw.Text(title.trim(), textDirection: dirOf(title), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)));
        body.add(pw.SizedBox(height: 10));
      }
      var n = 0;
      for (final bl in d.blocks) {
        if (bl.isEmbed) {
          n = 0;
          if (bl.embedType == Embeds.table) {
            final rows = bl.tableRows;
            if (rows.isEmpty) continue;
            final rtl = rows.any((r) => r.any(isRtlText)) || docRtl;
            final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
            List<String> pad(List<String> r) => [...r, ...List.filled(width - r.length, '')];
            final data = [for (final r in rows) rtl ? pad(r).reversed.toList() : pad(r)];
            body.add(pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.6),
                children: [
                  for (var i = 0; i < data.length; i++)
                    pw.TableRow(
                      decoration: i == 0 ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF2FF)) : null,
                      children: [
                        for (final c in data[i])
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(c, textDirection: dirOf(c), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: i == 0 ? pw.FontWeight.bold : null)),
                          ),
                      ],
                    ),
                ],
              ),
            ));
          } else if (bl.embedType == Embeds.divider) {
            body.add(pw.Divider(color: PdfColors.grey500));
          } else {
            final name = bl.embedMap['name']?.toString() ?? '';
            body.add(pw.Text('[$name]', textDirection: dirOf(name), style: const pw.TextStyle(color: PdfColors.grey700)));
          }
          continue;
        }
        n = bl.list == 'ordered' ? n + 1 : 0;
        final text = bl.text;
        final dir = dirOf(text);
        final h = bl.header;
        final prefix = switch (bl.list) {
          'bullet' => '• ',
          'ordered' => '$n. ',
          'checked' => '☑ ',
          'unchecked' => '☐ ',
          _ => '',
        };
        final spans = <pw.InlineSpan>[
          if (prefix.isNotEmpty) pw.TextSpan(text: prefix),
          for (final s in bl.segs)
            pw.TextSpan(
              text: s.text,
              style: pw.TextStyle(
                fontWeight: s.bold || h != null ? pw.FontWeight.bold : null,
                decoration: s.underline || s.link != null ? pw.TextDecoration.underline : (s.strike ? pw.TextDecoration.lineThrough : null),
                color: s.link != null ? PdfColors.blue700 : (s.color != null && s.color!.length >= 7 ? PdfColor.fromHex(s.color!.substring(0, 7)) : null),
              ),
            ),
        ];
        final size = h == 1 ? 18.0 : (h == 2 ? 15.5 : (h == 3 ? 13.5 : 11.5));
        pw.Widget w = pw.RichText(textDirection: dir, text: pw.TextSpan(children: spans, style: pw.TextStyle(fontSize: size)));
        if (bl.codeBlock) {
          w = pw.Container(
            width: double.infinity,
            color: const PdfColor.fromInt(0xFFF4F4F5),
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: pw.Text(text, textDirection: pw.TextDirection.ltr, style: const pw.TextStyle(fontSize: 10)),
          );
        } else if (bl.quote) {
          w = pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: pw.BoxDecoration(
              border: dir == pw.TextDirection.rtl
                  ? const pw.Border(right: pw.BorderSide(color: PdfColor.fromInt(0xFF6366F1), width: 3))
                  : const pw.Border(left: pw.BorderSide(color: PdfColor.fromInt(0xFF6366F1), width: 3)),
            ),
            child: w,
          );
        }
        final indent = bl.indent * 14.0;
        body.add(pw.Padding(
          padding: pw.EdgeInsets.only(top: h != null ? 8 : 2, bottom: 2, left: dir == pw.TextDirection.ltr ? indent : 0, right: dir == pw.TextDirection.rtl ? indent : 0),
          child: pw.Align(alignment: dir == pw.TextDirection.rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft, child: w),
        ));
      }
      doc.addPage(pw.MultiPage(
        textDirection: docRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => body.isEmpty ? [pw.SizedBox()] : body,
      ));
    }
    return doc.save();
  }

  // ------------------------------------------------------------------ import
  /// Imports a TXT / Markdown / HTML file as a new note. Returns the note id.
  Future<String> importFile(String name, List<int> bytes, {String? notebookId}) async {
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
    } catch (_) {
      throw const AppException('err_import_failed');
    }
    final (title, doc) = NoteFormat.import(name, text);
    return repo.createNote(title: title, content: doc.toJson(), notebookId: notebookId);
  }

  // ------------------------------------------------------------------ backup
  Future<String> backupText() async => jsonEncode({'format': format, 'version': 1, 'exported_at': nowIso(), 'data': await repo.dump()});

  Future<File> backup({String? password}) async {
    final text = await backupText();
    final enc = password != null && password.isNotEmpty;
    final f = File(p.join((await outDir()).path, 'notes_pro_backup_${dateKey(DateTime.now())}${enc ? '.npbk' : '.json'}'));
    await f.writeAsString(enc ? BackupCrypto.seal(text, password) : text, flush: true);
    return f;
  }

  /// A share file with one note, or every non-private note of one notebook
  /// (text only, no attachments). The other person imports it from "Import shared notes".
  Future<File> shareFile({String? noteId, String? notebookId}) async {
    final all = await repo.dump();
    final notes = <Map<String, Object?>>[
      for (final n in all['notes'] ?? const <Map<String, Object?>>[])
        if (n['deleted'] != 1 && n['is_private'] != 1 && n['is_private'] != true && (noteId != null ? n['id'] == noteId : n['notebook_id'] == notebookId)) n,
    ];
    if (notes.isEmpty) throw const AppException('err_nothing_to_share');
    final nbIds = {for (final n in notes) n['notebook_id']};
    final nbs = [for (final b in all['notebooks'] ?? const <Map<String, Object?>>[]) if (nbIds.contains(b['id'])) b];
    final text = jsonEncode({'format': format, 'version': 1, 'exported_at': nowIso(), 'data': {'notebooks': nbs, 'notes': notes}});
    final f = File(p.join((await outDir()).path, 'cmd_notes_share_${dateKey(DateTime.now())}.json'));
    await f.writeAsString(text, flush: true);
    return f;
  }

  static bool isEncryptedBackup(String text) => text.contains('"format":"${BackupCrypto.magic}"') || text.contains('"format": "${BackupCrypto.magic}"');

  Future<int> restore(String text, {String? password}) async {
    var plain = text;
    if (isEncryptedBackup(text)) {
      final o = password == null ? null : BackupCrypto.open(text, password);
      if (o == null) throw const AppException('err_backup_password');
      plain = o;
    }
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(plain) as Map<String, dynamic>;
    } catch (_) {
      throw const AppException('err_bad_backup');
    }
    if (j['format'] != format || j['data'] is! Map) throw const AppException('err_bad_backup');
    return repo.restoreBackup(Map<String, dynamic>.from(j['data'] as Map));
  }
}

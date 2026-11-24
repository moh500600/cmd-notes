import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/utils/text_tools.dart';
import 'delta_doc.dart';

/// Converts a note (title + delta) to TXT / Markdown / HTML / DOCX, and TXT / Markdown / HTML back
/// into a delta. Pure Dart (tested in test/export_test.dart). PDF lives in data/services (needs fonts).
class NoteFormat {
  // ------------------------------------------------------------------ export
  static String toTxt(String title, DeltaDoc doc) {
    final b = StringBuffer();
    if (title.trim().isNotEmpty) {
      b
        ..writeln(title.trim())
        ..writeln();
    }
    var n = 0;
    for (final bl in doc.blocks) {
      if (bl.isEmbed) {
        n = 0;
        if (bl.embedType == Embeds.table) {
          for (final r in bl.tableRows) {
            b.writeln(r.join('\t'));
          }
        } else if (bl.embedType == Embeds.divider) {
          b.writeln('—————');
        } else {
          b.writeln('[${bl.embedMap['name'] ?? ''}]');
        }
        continue;
      }
      n = bl.list == 'ordered' ? n + 1 : 0;
      b.writeln('${'  ' * bl.indent}${_bulletTxt(bl, n)}${bl.text}');
    }
    return b.toString();
  }

  static String _bulletTxt(Block bl, int n) => switch (bl.list) {
    'bullet' => '• ',
    'ordered' => '$n. ',
    'checked' => '☑ ',
    'unchecked' => '☐ ',
    _ => bl.quote ? '> ' : '',
  };

  static String _mdInline(Seg s) {
    var t = s.text.replaceAllMapped(RegExp(r'([*_`\[\]])'), (m) => '\\${m[1]}');
    if (s.code) t = '`${s.text}`';
    if (s.bold) t = '**$t**';
    if (s.italic) t = '*$t*';
    if (s.strike) t = '~~$t~~';
    if (s.underline) t = '<u>$t</u>';
    if (s.link != null) t = '[$t](${s.link})';
    return t;
  }

  static String toMarkdown(String title, DeltaDoc doc) {
    final b = StringBuffer();
    if (title.trim().isNotEmpty) {
      b
        ..writeln('# ${title.trim()}')
        ..writeln();
    }
    var n = 0;
    var inCode = false;
    for (final bl in doc.blocks) {
      if (inCode && !bl.codeBlock) {
        b.writeln('```');
        inCode = false;
      }
      if (bl.isEmbed) {
        n = 0;
        switch (bl.embedType) {
          case Embeds.table:
            final rows = bl.tableRows;
            if (rows.isNotEmpty) {
              b.writeln('| ${rows.first.join(' | ')} |');
              b.writeln('|${List.filled(rows.first.length, ' --- ').join('|')}|');
              for (final r in rows.skip(1)) {
                b.writeln('| ${r.join(' | ')} |');
              }
              b.writeln();
            }
          case Embeds.divider:
            b.writeln('\n---\n');
          default:
            b.writeln('📎 ${bl.embedMap['name'] ?? ''}');
        }
        continue;
      }
      if (bl.codeBlock) {
        if (!inCode) {
          b.writeln('```');
          inCode = true;
        }
        b.writeln(bl.text);
        continue;
      }
      n = bl.list == 'ordered' ? n + 1 : 0;
      final text = bl.segs.map(_mdInline).join();
      final pad = '  ' * bl.indent;
      final h = bl.header;
      if (h != null) {
        b.writeln('${'#' * (h + 1).clamp(2, 6)} $text');
      } else {
        b.writeln(switch (bl.list) {
          'bullet' => '$pad- $text',
          'ordered' => '$pad$n. $text',
          'checked' => '$pad- [x] $text',
          'unchecked' => '$pad- [ ] $text',
          _ => bl.quote ? '> $text' : text,
        });
      }
    }
    if (inCode) b.writeln('```');
    return b.toString();
  }

  static String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  static String _htmlInline(Seg s) {
    var t = _esc(s.text);
    if (s.code) t = '<code>$t</code>';
    if (s.bold) t = '<strong>$t</strong>';
    if (s.italic) t = '<em>$t</em>';
    if (s.underline) t = '<u>$t</u>';
    if (s.strike) t = '<s>$t</s>';
    final c = s.color;
    if (c != null && RegExp(r'^#[0-9a-fA-F]{6,8}$').hasMatch(c)) t = '<span style="color:${c.substring(0, 7)}">$t</span>';
    final size = s.attrs['size'];
    if (size != null) t = '<span style="font-size:${_cssSize(size)}">$t</span>';
    if (s.link != null) t = '<a href="${_esc(s.link!)}">$t</a>';
    return t;
  }

  static String _cssSize(Object v) => switch (v.toString()) {
    'small' => '0.8em',
    'large' => '1.3em',
    'huge' => '1.7em',
    final x => double.tryParse(x) != null ? '${x}px' : '1em',
  };

  static String toHtml(String title, DeltaDoc doc, {bool rtl = false}) {
    final b = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="${rtl ? 'ar' : 'en'}" dir="${rtl ? 'rtl' : 'ltr'}"><head><meta charset="utf-8">')
      ..writeln('<title>${_esc(title)}</title>')
      ..writeln('<style>body{font-family:Tajawal,"Segoe UI",Tahoma,sans-serif;max-width:820px;margin:24px auto;padding:0 16px;line-height:1.7}'
          'blockquote{border-inline-start:4px solid #6366F1;margin:0;padding:4px 12px;color:#555}'
          'pre{background:#f4f4f5;padding:12px;border-radius:8px;direction:ltr;text-align:left;overflow:auto}'
          'table{border-collapse:collapse;margin:8px 0}td,th{border:1px solid #ccc;padding:6px 10px}th{background:#eef}'
          'li.checked{list-style:"☑ "}li.unchecked{list-style:"☐ "}</style></head><body>');
    if (title.trim().isNotEmpty) b.writeln('<h1 dir="auto">${_esc(title.trim())}</h1>');
    String? openList;
    final code = StringBuffer();
    void closeList() {
      if (openList != null) b.writeln(openList == 'ordered' ? '</ol>' : '</ul>');
      openList = null;
    }

    void flushCode() {
      if (code.isNotEmpty) {
        b.writeln('<pre><code>${_esc(code.toString().trimRight())}</code></pre>');
        code.clear();
      }
    }

    for (final bl in doc.blocks) {
      if (!bl.codeBlock) flushCode();
      final listKind = bl.list == null ? null : (bl.list == 'ordered' ? 'ordered' : 'bullet');
      if (listKind != openList) closeList();
      if (bl.isEmbed) {
        switch (bl.embedType) {
          case Embeds.table:
            final rows = bl.tableRows;
            b.writeln('<table dir="auto">');
            for (var i = 0; i < rows.length; i++) {
              final tag = i == 0 ? 'th' : 'td';
              b.writeln('<tr>${rows[i].map((c) => '<$tag>${_esc(c)}</$tag>').join()}</tr>');
            }
            b.writeln('</table>');
          case Embeds.divider:
            b.writeln('<hr>');
          default:
            b.writeln('<p>📎 ${_esc(bl.embedMap['name']?.toString() ?? '')}</p>');
        }
        continue;
      }
      if (bl.codeBlock) {
        code.writeln(bl.text);
        continue;
      }
      final inner = bl.segs.map(_htmlInline).join();
      final align = bl.attrs['align'] is String ? ' style="text-align:${bl.attrs['align']}"' : '';
      if (listKind != null) {
        if (openList == null) {
          b.writeln(listKind == 'ordered' ? '<ol dir="auto">' : '<ul dir="auto">');
          openList = listKind;
        }
        final cls = bl.list == 'checked' || bl.list == 'unchecked' ? ' class="${bl.list}"' : '';
        b.writeln('<li$cls>$inner</li>');
      } else if (bl.header != null) {
        final h = (bl.header! + 1).clamp(2, 6);
        b.writeln('<h$h dir="auto"$align>$inner</h$h>');
      } else if (bl.quote) {
        b.writeln('<blockquote dir="auto">$inner</blockquote>');
      } else {
        b.writeln('<p dir="auto"$align>${inner.isEmpty ? '<br>' : inner}</p>');
      }
    }
    flushCode();
    closeList();
    b.writeln('</body></html>');
    return b.toString();
  }

  static String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  /// A Word document. Arabic paragraphs are marked right-to-left (w:bidi + w:rtl) so Word
  /// lays them out and orders table columns correctly.
  static List<int> toDocx(String title, DeltaDoc doc) {
    final body = StringBuffer();
    String para(String runs, {bool rtl = false, String? style, int? sizeHalfPts, bool bold = false, int indent = 0, String? shade}) {
      final ppr = StringBuffer('<w:pPr>');
      if (style != null) ppr.write('<w:pStyle w:val="$style"/>');
      if (shade != null) ppr.write('<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>');
      if (indent > 0) ppr.write('<w:ind w:start="${indent * 360}"/>');
      if (rtl) ppr.write('<w:bidi/><w:jc w:val="right"/>');
      ppr.write('</w:pPr>');
      return '<w:p>$ppr$runs</w:p>';
    }

    String run(String text, {bool rtl = false, bool bold = false, bool italic = false, bool underline = false, bool strike = false, String? color, int? size, bool mono = false}) {
      final rpr = StringBuffer('<w:rPr>');
      if (mono) rpr.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>');
      if (bold) rpr.write('<w:b/><w:bCs/>');
      if (italic) rpr.write('<w:i/><w:iCs/>');
      if (underline) rpr.write('<w:u w:val="single"/>');
      if (strike) rpr.write('<w:strike/>');
      if (color != null) rpr.write('<w:color w:val="$color"/>');
      if (size != null) rpr.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/>');
      if (rtl) rpr.write('<w:rtl/>');
      rpr.write('</w:rPr>');
      return '<w:r>$rpr<w:t xml:space="preserve">${_x(text)}</w:t></w:r>';
    }

    if (title.trim().isNotEmpty) {
      final rtl = isRtlText(title);
      body.write(para(run(title.trim(), rtl: rtl, bold: true, size: 40), rtl: rtl));
    }
    var n = 0;
    for (final bl in doc.blocks) {
      if (bl.isEmbed) {
        n = 0;
        if (bl.embedType == Embeds.table) {
          final rows = bl.tableRows;
          final rtl = rows.any((r) => r.any(isRtlText));
          body.write('<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblBorders>'
              '<w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/>'
              '<w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>');
          for (var i = 0; i < rows.length; i++) {
            body.write('<w:tr>');
            for (final c in rows[i]) {
              final cr = isRtlText(c) || (rtl && c.trim().isEmpty);
              body.write('<w:tc>${para(run(c, rtl: cr, bold: i == 0), rtl: cr)}</w:tc>');
            }
            body.write('</w:tr>');
          }
          body.write('</w:tbl>');
          body.write(para(''));
        } else if (bl.embedType == Embeds.divider) {
          body.write('<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="999999"/></w:pBdr></w:pPr></w:p>');
        } else {
          final name = bl.embedMap['name']?.toString() ?? '';
          body.write(para(run('📎 $name', rtl: isRtlText(name)), rtl: isRtlText(name)));
        }
        continue;
      }
      n = bl.list == 'ordered' ? n + 1 : 0;
      final rtl = isRtlText(bl.text) || bl.attrs['direction'] == 'rtl';
      final h = bl.header;
      final size = h == null ? null : (h == 1 ? 34 : (h == 2 ? 30 : 26));
      final prefix = _bulletTxt(bl, n);
      final runs = StringBuffer();
      if (prefix.isNotEmpty && !bl.quote) runs.write(run(prefix, rtl: rtl));
      for (final s in bl.segs) {
        runs.write(run(
          s.text,
          rtl: rtl,
          bold: s.bold || h != null,
          italic: s.italic,
          underline: s.underline || s.link != null,
          strike: s.strike,
          color: s.link != null ? '2563EB' : (s.color != null && s.color!.length >= 7 ? s.color!.substring(1, 7) : null),
          size: size,
          mono: s.code || bl.codeBlock,
        ));
      }
      body.write(para(runs.toString(), rtl: rtl, indent: bl.indent + (bl.quote ? 1 : 0), shade: bl.codeBlock ? 'F4F4F5' : (bl.quote ? 'EEF2FF' : null)));
    }
    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
    const types = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
    final a = Archive();
    for (final (name, text) in [('[Content_Types].xml', types), ('_rels/.rels', rels), ('word/document.xml', document)]) {
      final bytes = utf8.encode(text);
      a.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    return ZipEncoder().encode(a);
  }

  // ------------------------------------------------------------------ import
  static (String, DeltaDoc) fromTxt(String text, {String fallbackTitle = ''}) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final first = lines.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final title = first.trim().runes.length <= 120 && first.trim().isNotEmpty ? first.trim() : fallbackTitle;
    final rest = title == first.trim() && title.isNotEmpty ? lines.skip(lines.indexOf(first) + 1).join('\n').replaceFirst(RegExp(r'^\n+'), '') : text;
    return (title, DeltaDoc.fromPlain(rest));
  }

  static final _mdInlineRe = RegExp(r'(\*\*([^*]+)\*\*)|(__([^_]+)__)|(\*([^*]+)\*)|(_([^_]+)_)|(`([^`]+)`)|(~~([^~]+)~~)|(\[([^\]]+)\]\(([^)\s]+)\))');

  static List<Seg> _mdSegs(String s) {
    final out = <Seg>[];
    var i = 0;
    for (final m in _mdInlineRe.allMatches(s)) {
      if (m.start > i) out.add(Seg(_unesc(s.substring(i, m.start))));
      if (m[2] != null || m[4] != null) {
        out.add(Seg(m[2] ?? m[4]!, const {'bold': true}));
      } else if (m[6] != null || m[8] != null) {
        out.add(Seg(m[6] ?? m[8]!, const {'italic': true}));
      } else if (m[10] != null) {
        out.add(Seg(m[10]!, const {'code': true}));
      } else if (m[12] != null) {
        out.add(Seg(m[12]!, const {'strike': true}));
      } else if (m[14] != null) {
        out.add(Seg(m[14]!, {'link': m[15]}));
      }
      i = m.end;
    }
    if (i < s.length) out.add(Seg(_unesc(s.substring(i))));
    return out;
  }

  static String _unesc(String s) => s.replaceAllMapped(RegExp(r'\\([*_`\[\]\\])'), (m) => m[1]!);

  static (String, DeltaDoc) fromMarkdown(String md, {String fallbackTitle = '', bool takeTitle = true}) {
    final lines = md.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Block>[];
    var title = '';
    var inCode = false;
    final table = <List<String>>[];
    void flushTable() {
      if (table.isNotEmpty) {
        blocks.add(Block(const [], const {}, embedType: Embeds.table, embedData: jsonEncode({'rows': List.of(table)})));
        table.clear();
      }
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().startsWith('```')) {
        flushTable();
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        blocks.add(Block([Seg(raw)], const {'code-block': true}));
        continue;
      }
      final t = line.trim();
      if (t.startsWith('|') && t.endsWith('|') && t.length > 1) {
        final cells = t.substring(1, t.length - 1).split('|').map((c) => c.trim()).toList();
        if (cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) continue; // separator row
        table.add(cells);
        continue;
      }
      flushTable();
      final indent = ((raw.length - raw.trimLeft().length) ~/ 2).clamp(0, 5);
      final ind = indent > 0 ? <String, dynamic>{'indent': indent} : <String, dynamic>{};
      Match? m;
      if ((m = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t)) != null) {
        final level = m![1]!.length;
        if (takeTitle && level == 1 && title.isEmpty && blocks.isEmpty) {
          title = m[2]!.trim();
        } else {
          blocks.add(Block(_mdSegs(m[2]!), {'header': (level - 1).clamp(1, 3)}));
        }
      } else if ((m = RegExp(r'^[-*+]\s+\[( |x|X)\]\s*(.*)$').firstMatch(t)) != null) {
        blocks.add(Block(_mdSegs(m![2]!), {'list': m[1]!.trim().isEmpty ? 'unchecked' : 'checked', ...ind}));
      } else if ((m = RegExp(r'^[-*+]\s+(.*)$').firstMatch(t)) != null) {
        blocks.add(Block(_mdSegs(m![1]!), {'list': 'bullet', ...ind}));
      } else if ((m = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(t)) != null) {
        blocks.add(Block(_mdSegs(m![1]!), {'list': 'ordered', ...ind}));
      } else if ((m = RegExp(r'^>\s?(.*)$').firstMatch(t)) != null) {
        blocks.add(Block(_mdSegs(m![1]!), const {'blockquote': true}));
      } else if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(t)) {
        blocks.add(const Block([], {}, embedType: Embeds.divider, embedData: 'section'));
      } else {
        blocks.add(Block(_mdSegs(line), const {}));
      }
    }
    flushTable();
    return (title.isEmpty ? fallbackTitle : title, DeltaDoc.fromBlocks(blocks));
  }

  static (String, DeltaDoc) fromHtml(String html, {String fallbackTitle = ''}) {
    final d = html_parser.parse(html);
    var title = d.querySelector('title')?.text.trim() ?? '';
    final blocks = <Block>[];

    List<Seg> inline(dom.Node n, Map<String, dynamic> attrs) {
      if (n is dom.Text) {
        final t = n.text.replaceAll(RegExp(r'\s+'), ' ');
        return t.isEmpty ? const [] : [Seg(t, attrs)];
      }
      if (n is! dom.Element) return const [];
      final a = Map<String, dynamic>.from(attrs);
      switch (n.localName) {
        case 'b' || 'strong':
          a['bold'] = true;
        case 'i' || 'em':
          a['italic'] = true;
        case 'u':
          a['underline'] = true;
        case 's' || 'strike' || 'del':
          a['strike'] = true;
        case 'code':
          a['code'] = true;
        case 'a':
          if (n.attributes['href'] != null) a['link'] = n.attributes['href'];
        case 'br':
          return const [Seg('\n')];
      }
      final style = n.attributes['style'] ?? '';
      final color = RegExp(r'color\s*:\s*(#[0-9a-fA-F]{6})').firstMatch(style)?[1];
      if (color != null) a['color'] = color;
      return [for (final c in n.nodes) ...inline(c, a)];
    }

    void addLines(List<Seg> segs, Map<String, dynamic> blockAttrs) {
      // a <br> inside a paragraph starts a new line with the same block attributes
      var cur = <Seg>[];
      for (final s in segs) {
        if (s.text == '\n') {
          blocks.add(Block(cur, blockAttrs));
          cur = [];
        } else {
          cur.add(s);
        }
      }
      if (cur.isNotEmpty || segs.isEmpty) {
        final trimmed = cur.isEmpty ? cur : [Seg(cur.first.text.trimLeft(), cur.first.attrs), ...cur.skip(1)];
        blocks.add(Block(trimmed.where((s) => s.text.isNotEmpty).toList(), blockAttrs));
      }
    }

    void walk(dom.Element e, {String? list, int depth = 0}) {
      for (final n in e.nodes) {
        if (n is dom.Text) {
          if (n.text.trim().isNotEmpty) addLines(inline(n, const {}), const {});
          continue;
        }
        if (n is! dom.Element) continue;
        switch (n.localName) {
          case 'h1':
            if (title.isEmpty && blocks.isEmpty) {
              title = n.text.trim();
            } else {
              addLines(inline(n, const {}), const {'header': 1});
            }
          case 'h2':
            addLines(inline(n, const {}), const {'header': 1});
          case 'h3':
            addLines(inline(n, const {}), const {'header': 2});
          case 'h4' || 'h5' || 'h6':
            addLines(inline(n, const {}), const {'header': 3});
          case 'p' || 'div' when n.querySelector('p,div,ul,ol,table,h1,h2,h3,h4,pre,blockquote') == null:
            addLines([for (final c in n.nodes) ...inline(c, const {})], const {});
          case 'p' || 'div' || 'section' || 'article' || 'main' || 'body':
            walk(n, list: list, depth: depth);
          case 'ul' || 'ol':
            walk(n, list: n.localName == 'ol' ? 'ordered' : 'bullet', depth: list == null ? 0 : depth + 1);
          case 'li':
            final input = n.querySelector('input[type=checkbox]');
            final cls = n.attributes['class'] ?? '';
            final kind = input != null
                ? (input.attributes.containsKey('checked') ? 'checked' : 'unchecked')
                : (cls.contains('unchecked') ? 'unchecked' : (cls.contains('checked') ? 'checked' : (list ?? 'bullet')));
            final own = [for (final c in n.nodes) if (!(c is dom.Element && (c.localName == 'ul' || c.localName == 'ol'))) ...inline(c, const {})];
            addLines(own, {'list': kind, if (depth > 0) 'indent': depth});
            for (final sub in n.children.where((c) => c.localName == 'ul' || c.localName == 'ol')) {
              walk(sub, list: sub.localName == 'ol' ? 'ordered' : 'bullet', depth: depth + 1);
            }
          case 'blockquote':
            addLines(inline(n, const {}), const {'blockquote': true});
          case 'pre':
            for (final l in n.text.trimRight().split('\n')) {
              blocks.add(Block([Seg(l)], const {'code-block': true}));
            }
          case 'hr':
            blocks.add(const Block([], {}, embedType: Embeds.divider, embedData: 'section'));
          case 'table':
            final rows = [
              for (final tr in n.querySelectorAll('tr')) [for (final c in tr.children.where((c) => c.localName == 'td' || c.localName == 'th')) c.text.trim()],
            ].where((r) => r.isNotEmpty).toList();
            if (rows.isNotEmpty) blocks.add(Block(const [], const {}, embedType: Embeds.table, embedData: jsonEncode({'rows': rows})));
          case 'head' || 'script' || 'style' || 'title' || 'meta':
            break;
          default:
            addLines(inline(n, const {}), const {});
        }
      }
    }

    final body = d.body ?? d.documentElement;
    if (body != null) walk(body);
    return (title.isEmpty ? fallbackTitle : title, DeltaDoc.fromBlocks(blocks));
  }

  /// Picks the importer by file extension.
  static (String, DeltaDoc) import(String fileName, String text) {
    final lower = fileName.toLowerCase();
    final base = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) return fromMarkdown(text, fallbackTitle: base);
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return fromHtml(text, fallbackTitle: base);
    return fromTxt(text, fallbackTitle: base);
  }
}

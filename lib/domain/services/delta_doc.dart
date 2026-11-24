import 'dart:convert';

/// The note body is a Quill Delta (JSON list of ops). This file reads it without Flutter so
/// search, counters, export and tests share one parser.
///
/// Custom block embeds used by the editor:
///   np-image   {"id": attachmentId, "name": "photo.jpg"}
///   np-file    {"id": attachmentId, "name": "report.pdf"}
///   np-table   {"rows": [["a","b"],["c","d"]]}   (first row = header)
///   np-divider "section"                          (a section break)
class Embeds {
  static const image = 'np-image';
  static const file = 'np-file';
  static const table = 'np-table';
  static const divider = 'np-divider';
}

class Seg {
  final String text;
  final Map<String, dynamic> attrs;
  const Seg(this.text, [this.attrs = const {}]);
  bool get bold => attrs['bold'] == true;
  bool get italic => attrs['italic'] == true;
  bool get underline => attrs['underline'] == true;
  bool get strike => attrs['strike'] == true;
  bool get code => attrs['code'] == true;
  String? get link => attrs['link'] as String?;
  String? get color => attrs['color'] as String?;
}

/// One line (paragraph) or one block embed.
class Block {
  final List<Seg> segs;
  final Map<String, dynamic> attrs; // header, list, blockquote, code-block, align, direction, indent
  final String? embedType;
  final dynamic embedData;
  const Block(this.segs, this.attrs, {this.embedType, this.embedData});

  bool get isEmbed => embedType != null;
  String get text => segs.map((s) => s.text).join();
  int? get header => attrs['header'] is int ? attrs['header'] as int : null;
  String? get list => attrs['list'] as String?; // bullet | ordered | checked | unchecked
  bool get quote => attrs['blockquote'] == true;
  bool get codeBlock => attrs['code-block'] == true;
  int get indent => attrs['indent'] is int ? attrs['indent'] as int : 0;

  Map<String, dynamic> get embedMap {
    final d = embedData;
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.startsWith('{')) {
      try {
        return Map<String, dynamic>.from(jsonDecode(d) as Map);
      } catch (_) {}
    }
    return const {};
  }

  List<List<String>> get tableRows {
    final rows = embedMap['rows'];
    if (rows is! List) return const [];
    return [
      for (final r in rows)
        if (r is List) [for (final c in r) c?.toString() ?? ''],
    ];
  }
}

class DeltaDoc {
  final List<Map<String, dynamic>> ops;
  DeltaDoc(this.ops);

  static DeltaDoc parse(String? json) {
    if (json == null || json.trim().isEmpty) return DeltaDoc([]);
    try {
      final v = jsonDecode(json);
      if (v is List) return DeltaDoc([for (final o in v) if (o is Map) Map<String, dynamic>.from(o)]);
      if (v is Map && v['ops'] is List) return DeltaDoc([for (final o in v['ops'] as List) if (o is Map) Map<String, dynamic>.from(o)]);
    } catch (_) {}
    // Not JSON: treat as plain text.
    return fromPlain(json);
  }

  /// Plain text → delta (one op per line, every line ends with \n as Quill requires).
  static DeltaDoc fromPlain(String text) {
    final t = text.replaceAll('\r\n', '\n');
    return DeltaDoc([
      {'insert': t.endsWith('\n') ? t : '$t\n'},
    ]);
  }

  static DeltaDoc fromBlocks(List<Block> blocks) {
    final ops = <Map<String, dynamic>>[];
    for (final b in blocks) {
      if (b.isEmbed) {
        ops.add({
          'insert': {b.embedType!: b.embedData is String ? b.embedData : jsonEncode(b.embedData)},
        });
        ops.add({'insert': '\n'});
        continue;
      }
      for (final s in b.segs) {
        if (s.text.isEmpty) continue;
        ops.add({'insert': s.text, if (s.attrs.isNotEmpty) 'attributes': s.attrs});
      }
      ops.add({'insert': '\n', if (b.attrs.isNotEmpty) 'attributes': b.attrs});
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    return DeltaDoc(ops);
  }

  String toJson() => jsonEncode(ops.isEmpty ? [{'insert': '\n'}] : ops);

  /// Lines and embeds, in order.
  List<Block> get blocks {
    final out = <Block>[];
    var segs = <Seg>[];
    for (final op in ops) {
      final ins = op['insert'];
      final attrs = op['attributes'] is Map ? Map<String, dynamic>.from(op['attributes'] as Map) : <String, dynamic>{};
      if (ins is String) {
        final parts = ins.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) segs.add(Seg(parts[i], attrs));
          if (i < parts.length - 1) {
            out.add(Block(segs, attrs)); // the attributes of a "\n" op are the line's block attributes
            segs = <Seg>[];
          }
        }
      } else if (ins is Map && ins.isNotEmpty) {
        if (segs.isNotEmpty) {
          out.add(Block(segs, const {}));
          segs = <Seg>[];
        }
        final k = ins.keys.first.toString();
        out.add(Block(const [], attrs, embedType: k, embedData: ins[k]));
      }
    }
    if (segs.isNotEmpty) out.add(Block(segs, const {}));
    // A block embed is followed by its own "\n" line in Quill; drop that empty line.
    final cleaned = <Block>[];
    for (var i = 0; i < out.length; i++) {
      if (i > 0 && out[i - 1].isEmbed && !out[i].isEmbed && out[i].segs.isEmpty && out[i].attrs.isEmpty) continue;
      cleaned.add(out[i]);
    }
    return cleaned;
  }

  /// Searchable/plain text: lines, check items, table cells and file names included.
  String get plainText {
    final b = StringBuffer();
    for (final bl in blocks) {
      if (bl.isEmbed) {
        switch (bl.embedType) {
          case Embeds.table:
            for (final r in bl.tableRows) {
              b.writeln(r.join(' | '));
            }
          case Embeds.file || Embeds.image:
            final n = bl.embedMap['name']?.toString() ?? '';
            if (n.isNotEmpty) b.writeln(n);
          default:
            b.writeln();
        }
      } else {
        b.writeln(bl.text);
      }
    }
    return b.toString().trimRight();
  }

  /// Attachment ids referenced by image/file embeds.
  Set<String> get attachmentIds => {
    for (final bl in blocks)
      if ((bl.embedType == Embeds.image || bl.embedType == Embeds.file) && bl.embedMap['id'] != null) bl.embedMap['id'].toString(),
  };

  /// (done, total) check-list items.
  (int, int) get checklist {
    var done = 0, total = 0;
    for (final bl in blocks) {
      if (bl.list == 'checked') {
        done++;
        total++;
      } else if (bl.list == 'unchecked') {
        total++;
      }
    }
    return (done, total);
  }
}

/// Builder for template / import / AI deltas.
class DeltaBuilder {
  final _blocks = <Block>[];
  DeltaBuilder h(int level, String t) => _add(t, {'header': level});
  DeltaBuilder p(String t, [Map<String, dynamic> inline = const {}]) {
    _blocks.add(Block([Seg(t, inline)], const {}));
    return this;
  }

  DeltaBuilder bullet(String t) => _add(t, {'list': 'bullet'});
  DeltaBuilder ordered(String t) => _add(t, {'list': 'ordered'});
  DeltaBuilder check(String t, {bool done = false}) => _add(t, {'list': done ? 'checked' : 'unchecked'});
  DeltaBuilder quote(String t) => _add(t, {'blockquote': true});
  DeltaBuilder code(String t) {
    for (final line in t.split('\n')) {
      _add(line, {'code-block': true});
    }
    return this;
  }

  DeltaBuilder blank() => _add('', const {});
  DeltaBuilder divider() {
    _blocks.add(const Block([], {}, embedType: Embeds.divider, embedData: 'section'));
    return this;
  }

  DeltaBuilder table(List<List<String>> rows) {
    _blocks.add(Block(const [], const {}, embedType: Embeds.table, embedData: jsonEncode({'rows': rows})));
    return this;
  }

  DeltaBuilder raw(Block b) {
    _blocks.add(b);
    return this;
  }

  DeltaBuilder _add(String t, Map<String, dynamic> attrs) {
    _blocks.add(Block(t.isEmpty ? const [] : [Seg(t)], attrs));
    return this;
  }

  DeltaDoc build() => DeltaDoc.fromBlocks(_blocks);
  String json() => build().toJson();
}

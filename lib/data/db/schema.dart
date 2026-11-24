import 'package:decimal/decimal.dart';

import '../../core/utils/time.dart';

part 'schema_tables.g.dart';

/// Column types shared by the local SQLite schema and the server (`notes` schema).
enum ColType { uuid, text, integer, boolean, decimal, date, timestamp }

class Col {
  final String name;
  final ColType type;
  final bool nullable;
  final Object? def;

  /// Encrypted at rest in the device database (see FieldCipher); plain on the wire (TLS) and on the server (RLS).
  final bool secret;
  const Col(this.name, this.type, {this.nullable = false, this.def, this.secret = false});

  String get sqliteType => switch (type) {
    ColType.integer || ColType.boolean => 'INTEGER',
    _ => 'TEXT',
  };

  /// Default for a non-null column when a row does not set it.
  Object? get localDefault {
    if (def != null) return def;
    if (nullable) return null;
    return switch (type) {
      ColType.text => '',
      ColType.boolean || ColType.integer => 0,
      ColType.decimal => '0',
      _ => null,
    };
  }
}

/// One synced table. Every table also has the common columns
/// id, user_id, created_at, updated_at, deleted (+ local `dirty`).
class TableDef {
  final String name;
  final List<Col> cols;
  const TableDef(this.name, this.cols);

  static const common = [
    Col('id', ColType.uuid),
    Col('user_id', ColType.text),
    Col('created_at', ColType.timestamp),
    Col('updated_at', ColType.timestamp),
    Col('deleted', ColType.boolean),
  ];

  List<Col> get allCols => [...common, ...cols];

  /// Columns encrypted in the device database.
  List<String> get secretCols => [
    for (final c in cols)
      if (c.secret) c.name,
  ];

  String createSql() {
    final b = StringBuffer(
      'CREATE TABLE IF NOT EXISTS $name (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, '
      'created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1',
    );
    for (final c in cols) {
      b.write(', ${c.name} ${c.sqliteType}');
      if (!c.nullable) {
        final d = c.localDefault;
        b.write(' NOT NULL');
        if (d != null) b.write(d is String ? " DEFAULT '${d.replaceAll("'", "''")}'" : ' DEFAULT $d');
      }
    }
    b.write(')');
    return b.toString();
  }

  /// Local row → JSON for the server (drops `dirty`; booleans become true/false).
  Map<String, Object?> toRemote(Map<String, Object?> row) {
    final out = <String, Object?>{};
    for (final c in allCols) {
      final v = row[c.name];
      out[c.name] = switch (c.type) {
        ColType.boolean => v == null ? (c.nullable ? null : false) : (v == 1 || v == true),
        ColType.decimal => v?.toString(),
        _ => v,
      };
    }
    return out;
  }

  /// Server JSON → local row (normalised timestamps, decimals as exact text).
  Map<String, Object?> fromRemote(Map<String, dynamic> json) {
    final out = <String, Object?>{};
    for (final c in allCols) {
      if (!json.containsKey(c.name)) continue;
      final v = json[c.name];
      out[c.name] = switch (c.type) {
        ColType.boolean => v == true ? 1 : 0,
        ColType.integer => v == null ? null : (v as num).toInt(),
        ColType.decimal => v == null ? null : _decText(v),
        ColType.timestamp => normalizeIso(v),
        ColType.date => v?.toString().substring(0, 10),
        _ => v?.toString(),
      };
    }
    return out;
  }

  static String _decText(Object v) {
    final d = Decimal.tryParse(v.toString());
    return d == null ? v.toString() : d.toString();
  }
}

const _t = ColType.text, _i = ColType.integer, _b = ColType.boolean, _u = ColType.uuid;
const _date = ColType.date, _ts = ColType.timestamp;

TableDef tableDef(String name) => kTables.firstWhere((t) => t.name == name);

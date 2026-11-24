import 'package:sqflite/sqflite.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/time.dart';
import '../security/field_cipher.dart';
import 'schema.dart';

/// How deleting a row reaches related rows.
class _Link {
  final String table;
  final String column;
  final bool tombstone; // true: the related row is deleted too; false: the column is cleared
  final String? kindColumn;
  final String? kindValue;
  const _Link(this.table, this.column, {this.tombstone = true, this.kindColumn, this.kindValue});
}

const Map<String, List<_Link>> _links = {
  // Deleting a notebook deletes its sub-folders; its notes and recordings stay (moved out to "no notebook").
  'notebooks': [_Link('notebooks', 'parent_id'), _Link('notes', 'notebook_id', tombstone: false), _Link('voice_recordings', 'notebook_id', tombstone: false)],
  // Deleting a note for good removes its tags links, files and its recordings' link (recordings stay).
  'notes': [_Link('note_tags', 'note_id'), _Link('attachments', 'note_id'), _Link('voice_recordings', 'note_id', tombstone: false)],
  'tags': [_Link('note_tags', 'tag_id')],
  'journal_entries': [_Link('attachments', 'owner_id', kindColumn: 'owner_kind', kindValue: 'journal')],
};

/// Offline-first row store. Every write stamps `updated_at`, marks the row
/// `dirty` (to be pushed) and notifies [onChange]. Deletes are tombstones.
class LocalStore {
  final Database db;
  void Function(String table)? onChange;

  /// Encrypts the `secret` columns at rest (null = plain, used by some tests).
  final FieldCipher? cipher;
  LocalStore(this.db, {this.onChange, this.cipher});

  Map<String, Object?> _open(String table, Map<String, Object?> r) => cipher == null ? r : cipher!.openRow(table, r);

  String _lastStamp = '';

  /// A timestamp strictly after the previous one this store produced, so two
  /// quick edits of one row never share an `updated_at` (last-write-wins key).
  String stamp() {
    var s = nowIso();
    if (s.compareTo(_lastStamp) <= 0) {
      final t = DateTime.parse(_lastStamp).add(const Duration(milliseconds: 1));
      s = isoUtc(t);
    }
    return _lastStamp = s;
  }

  /// Live rows of [uid] (secret columns decrypted). Do not filter on secret columns in [where].
  Future<List<Map<String, Object?>>> all(String table, String uid, {String? where, List<Object?> args = const [], String? orderBy}) async {
    final rows = await db.query(
      table,
      where: 'user_id = ? AND deleted = 0${where == null ? '' : ' AND ($where)'}',
      whereArgs: [uid, ...args],
      orderBy: orderBy,
    );
    return cipher == null ? rows : [for (final r in rows) _open(table, r)];
  }

  Future<Map<String, Object?>?> get(String table, String id) async {
    final r = (await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1)).firstOrNull;
    return r == null ? null : _open(table, r);
  }

  /// Inserts or updates [row] (an `id` is created when missing). Returns the id.
  Future<String> save(String table, String uid, Map<String, Object?> row, {DatabaseExecutor? txn, bool notify = true}) async {
    final ex = txn ?? db;
    final def = tableDef(table);
    final id = (row['id'] as String?) ?? newId();
    final existing = (await ex.query(table, where: 'id = ?', whereArgs: [id], limit: 1)).firstOrNull;
    final now = stamp();
    final out = <String, Object?>{};
    for (final c in def.cols) {
      if (row.containsKey(c.name)) {
        var v = row[c.name];
        if (v is bool) v = v ? 1 : 0;
        if (c.type == ColType.decimal && v is num) v = v.toString();
        out[c.name] = v ?? (c.nullable ? null : c.localDefault);
      } else if (existing == null) {
        out[c.name] = c.localDefault;
      }
    }
    out['updated_at'] = now;
    out['dirty'] = 1;
    if (cipher != null) out.addAll(cipher!.sealRow(table, out));
    if (existing == null) {
      out['id'] = id;
      out['user_id'] = uid;
      out['created_at'] = row['created_at'] ?? now;
      out['deleted'] = 0;
      await ex.insert(table, out);
    } else {
      out['deleted'] = row['deleted'] ?? existing['deleted'];
      await ex.update(table, out, where: 'id = ?', whereArgs: [id]);
    }
    if (notify) onChange?.call(table);
    return id;
  }

  /// Tombstones [id] and, per the table's links, its children (or clears their reference).
  Future<void> delete(String table, String id) async {
    await db.transaction((txn) => _delete(txn, table, id));
    onChange?.call(table);
  }

  Future<void> _delete(Transaction txn, String table, String id) async {
    final now = stamp();
    await txn.update(table, {'deleted': 1, 'dirty': 1, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
    for (final l in _links[table] ?? const <_Link>[]) {
      final where = '${l.column} = ? AND deleted = 0${l.kindColumn == null ? '' : ' AND ${l.kindColumn} = ?'}';
      final args = [id, if (l.kindValue != null) l.kindValue];
      if (l.tombstone) {
        final kids = await txn.query(l.table, columns: ['id'], where: where, whereArgs: args);
        for (final k in kids) {
          await _delete(txn, l.table, k['id'] as String);
        }
      } else {
        await txn.update(l.table, {l.column: null, 'dirty': 1, 'updated_at': stamp()}, where: where, whereArgs: args);
      }
    }
  }

  /// Rows written while signed out (guest) become the account's rows, to be pushed.
  Future<int> adopt(String fromUid, String toUid) async {
    var n = 0;
    await db.transaction((txn) async {
      for (final t in kTables) {
        if (t.name == 'profiles') {
          final mine = await txn.query('profiles', where: 'id = ?', whereArgs: [toUid]);
          if (mine.isEmpty) {
            await txn.update('profiles', {'id': toUid}, where: 'user_id = ? AND id = ?', whereArgs: [fromUid, fromUid]);
          } else {
            await txn.delete('profiles', where: 'user_id = ?', whereArgs: [fromUid]);
          }
        }
        n += await txn.update(t.name, {'user_id': toUid, 'dirty': 1}, where: 'user_id = ?', whereArgs: [fromUid]);
      }
      await txn.update('drafts', {'user_id': toUid}, where: 'user_id = ?', whereArgs: [fromUid]);
      try {
        await txn.update('search_fts', {'user_id': toUid}, where: 'user_id = ?', whereArgs: [fromUid]);
      } catch (_) {}
    });
    onChange?.call('*');
    return n;
  }

  /// Counts rows waiting to be pushed.
  Future<int> pendingCount(String uid) async {
    var n = 0;
    for (final t in kTables) {
      n += (await db.rawQuery('SELECT COUNT(*) AS c FROM ${t.name} WHERE user_id = ? AND dirty = 1', [uid])).first['c'] as int;
    }
    return n;
  }

  /// Removes every row of [uid] from this device (not from the cloud).
  Future<void> wipe(String uid) async {
    await db.transaction((txn) async {
      for (final t in kTables) {
        await txn.delete(t.name, where: 'user_id = ?', whereArgs: [uid]);
      }
      await txn.delete('sync_state', where: 'user_id = ?', whereArgs: [uid]);
      await txn.delete('drafts', where: 'user_id = ?', whereArgs: [uid]);
      try {
        await txn.delete('search_fts', where: 'user_id = ?', whereArgs: [uid]);
      } catch (_) {}
    });
    onChange?.call('*');
  }
}

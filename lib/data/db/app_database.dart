import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// The device database. One table per synced entity (see [kTables]) plus
/// `sync_state` (pull cursors), `drafts` (crash-safe editor buffer) and the full-text index.
class AppDatabase {
  static const version = 1;

  static Future<Database> open(DatabaseFactory factory, String path) => factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
        // WAL: a crash mid-write never corrupts the file; readers never block the autosave.
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = NORMAL');
        } catch (_) {}
      },
      onCreate: (db, v) async => create(db),
      onUpgrade: (db, from, to) async => create(db),
      onOpen: (db) async => create(db),
    ),
  );

  /// Creates every table and index (idempotent).
  static Future<void> create(DatabaseExecutor db) async {
    for (final t in kTables) {
      await db.execute(t.createSql());
      await db.execute('CREATE INDEX IF NOT EXISTS ix_${t.name}_user ON ${t.name}(user_id, deleted)');
      await db.execute('CREATE INDEX IF NOT EXISTS ix_${t.name}_dirty ON ${t.name}(dirty)');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS ix_notes_nb ON notes(notebook_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS ix_note_tags_note ON note_tags(note_id)');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS sync_state (user_id TEXT NOT NULL, tbl TEXT NOT NULL, cursor TEXT, '
      'PRIMARY KEY (user_id, tbl))',
    );
    await db.execute('CREATE TABLE IF NOT EXISTS sync_meta (user_id TEXT PRIMARY KEY, last_sync_at TEXT, last_error TEXT)');
    // Editor buffer: written within a fraction of a second of every keystroke pause; applied to
    // the note on save, or recovered on the next start if the app was killed before that.
    await db.execute(
      'CREATE TABLE IF NOT EXISTS drafts (note_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL, '
      'content TEXT NOT NULL, saved_at TEXT NOT NULL)',
    );
  }
}

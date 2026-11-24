import 'package:sqflite/sqflite.dart';

import '../../core/utils/text_tools.dart';

/// Which full-text engine this device's SQLite offers.
enum FtsMode { fts5, fts4, plain }

class SearchHit {
  final String kind; // note | voice
  final String id;
  final double rank; // lower = better
  const SearchHit(this.kind, this.id, this.rank);
}

/// Instant local full-text search over titles, note text, folder names, tags, attachment
/// names, text read from images and voice transcripts — all normalised for Arabic
/// (see normalizeForSearch) so "مشروع" finds "مَشروع" and "اسامة" finds "أسامة".
///
/// SQLite FTS5 when available (it is in the SQLite bundled with the app), FTS4 otherwise,
/// and a plain LIKE table as the last resort, so search always works.
class SearchIndex {
  final Database db;
  FtsMode mode = FtsMode.plain;
  SearchIndex(this.db);

  static const _cols = 'title, body, folder, tags, files, voice';

  Future<FtsMode> init() async {
    final existing = (await db.rawQuery("SELECT sql FROM sqlite_master WHERE name = 'search_fts'")).firstOrNull?['sql']?.toString() ?? '';
    if (existing.isNotEmpty) {
      mode = existing.contains('fts5') ? FtsMode.fts5 : (existing.contains('fts4') ? FtsMode.fts4 : FtsMode.plain);
      return mode;
    }
    try {
      await db.execute(
        "CREATE VIRTUAL TABLE search_fts USING fts5(kind UNINDEXED, id UNINDEXED, user_id UNINDEXED, $_cols, tokenize = 'unicode61 remove_diacritics 2')",
      );
      return mode = FtsMode.fts5;
    } catch (_) {}
    try {
      await db.execute('CREATE VIRTUAL TABLE search_fts USING fts4(kind, id, user_id, $_cols, notindexed=kind, notindexed=id, notindexed=user_id, tokenize=unicode61)');
      return mode = FtsMode.fts4;
    } catch (_) {}
    await db.execute('CREATE TABLE IF NOT EXISTS search_fts (kind TEXT, id TEXT, user_id TEXT, title TEXT, body TEXT, folder TEXT, tags TEXT, files TEXT, voice TEXT)');
    return mode = FtsMode.plain;
  }

  /// Replaces the index entry of one note / recording (text is normalised here).
  Future<void> put(String kind, String id, String uid, {String title = '', String body = '', String folder = '', String tags = '', String files = '', String voice = ''}) async {
    await remove(kind, id);
    await db.insert('search_fts', {
      'kind': kind,
      'id': id,
      'user_id': uid,
      'title': normalizeForSearch(title),
      'body': normalizeForSearch(body),
      'folder': normalizeForSearch(folder),
      'tags': normalizeForSearch(tags),
      'files': normalizeForSearch(files),
      'voice': normalizeForSearch(voice),
    });
  }

  Future<void> remove(String kind, String id) => db.delete('search_fts', where: 'kind = ? AND id = ?', whereArgs: [kind, id]);

  Future<void> clear(String uid) => db.delete('search_fts', where: 'user_id = ?', whereArgs: [uid]);

  /// Best matches first.
  Future<List<SearchHit>> search(String uid, String query, {int limit = 200}) async {
    if (mode == FtsMode.plain) return _like(uid, query, limit);
    final m = ftsQuery(query);
    if (m == null) return const [];
    try {
      final rows = mode == FtsMode.fts5
          ? await db.rawQuery(
              // title and tags weigh more than body text
              'SELECT kind, id, bm25(search_fts, 0, 0, 0, 8.0, 1.0, 3.0, 4.0, 2.0, 1.5) AS r FROM search_fts WHERE search_fts MATCH ? AND user_id = ? ORDER BY r LIMIT ?',
              [m, uid, limit],
            )
          : await db.rawQuery('SELECT kind, id, 0 AS r FROM search_fts WHERE search_fts MATCH ? AND user_id = ? LIMIT ?', [m, uid, limit]);
      return [for (final r in rows) SearchHit(r['kind'] as String, r['id'] as String, (r['r'] as num?)?.toDouble() ?? 0)];
    } catch (_) {
      return _like(uid, query, limit);
    }
  }

  Future<List<SearchHit>> _like(String uid, String query, int limit) async {
    final words = searchTokens(query);
    if (words.isEmpty) return const [];
    final where = words.map((_) => "(title || ' ' || body || ' ' || folder || ' ' || tags || ' ' || files || ' ' || voice) LIKE ?").join(' AND ');
    final rows = await db.rawQuery('SELECT kind, id FROM search_fts WHERE user_id = ? AND $where LIMIT ?', [uid, for (final w in words) '%$w%', limit]);
    return [for (final r in rows) SearchHit(r['kind'] as String, r['id'] as String, 0)];
  }
}

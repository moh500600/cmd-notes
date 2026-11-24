import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/text_tools.dart';
import '../../core/utils/time.dart';
import '../../domain/entities/entities.dart';
import '../../domain/services/delta_doc.dart';
import '../../domain/services/folder_tree.dart';
import '../../domain/services/notes_data.dart';
import '../../domain/services/trash.dart';
import '../db/local_store.dart';
import '../db/schema.dart';
import '../db/search_index.dart';
import '../security/field_cipher.dart';

/// The decrypted body of a private note.
class OpenedNote {
  final String content;
  final String plain;
  const OpenedNote(this.content, this.plain);
}

/// All reads and writes of the signed-in user's notes (offline-first: the device DB).
class NotesRepository {
  final LocalStore store;
  final SearchIndex index;
  final String uid;

  /// The unlocked private-notes vault (null while locked).
  AesGcmFieldCipher? vault;

  NotesRepository(this.store, this.index, this.uid, {this.vault});

  // ------------------------------------------------------------------ load
  Future<NotesData> load() async {
    final rows = await Future.wait([
      store.all('notes', uid),
      store.all('notebooks', uid),
      store.all('tags', uid, orderBy: 'name COLLATE NOCASE'),
      store.all('note_tags', uid),
      store.all('templates', uid, orderBy: 'name COLLATE NOCASE'),
      store.all('attachments', uid),
      store.all('voice_recordings', uid, orderBy: 'created_at DESC'),
      store.all('journal_entries', uid, orderBy: 'entry_date DESC'),
      store.all('profiles', uid),
    ]);
    return NotesData(
      uid: uid,
      notes: rows[0].map(Note.new).toList(),
      notebooks: rows[1].map(Notebook.new).toList(),
      tags: rows[2].map(Tag.new).toList(),
      noteTags: rows[3].map(NoteTag.new).toList(),
      templates: rows[4].map(NoteTemplate.new).toList(),
      attachments: rows[5].map(Attachment.new).toList(),
      voices: rows[6].map(VoiceRecording.new).toList(),
      journal: rows[7].map(JournalEntry.new).toList(),
      profile: rows[8].isEmpty ? null : Profile(rows[8].first),
    );
  }

  Future<Note?> note(String id) async {
    final r = await store.get('notes', id);
    return r == null || r['deleted'] == 1 ? null : Note(r);
  }

  Future<String> save(String table, Map<String, Object?> row) => store.save(table, uid, row);
  Future<void> delete(String table, String id) => store.delete(table, id);

  // ------------------------------------------------------------------ notes
  Future<String> createNote({String type = 'text', String? notebookId, String title = '', String? content, String templateKey = '', DateTime? eventAt}) async {
    final doc = DeltaDoc.parse(content);
    final plain = doc.plainText;
    final id = await store.save('notes', uid, {
      'notebook_id': notebookId,
      'title': title,
      'content': doc.toJson(),
      'plain_text': plain,
      'note_type': type,
      'template_key': templateKey,
      'word_count': wordCount('$title $plain'),
      'char_count': charCount(plain),
      'event_at': eventAt == null ? null : isoUtc(eventAt),
    });
    await reindexNote(id);
    return id;
  }

  /// The editor's autosave: title + delta → note row (+ counts, search index). Clears the draft.
  /// Private notes are encrypted before they touch the database.
  Future<void> saveContent(String id, String title, String deltaJson) async {
    final n = await note(id);
    if (n == null) return;
    final doc = DeltaDoc.parse(deltaJson);
    final plain = doc.plainText;
    final row = <String, Object?>{
      'id': id,
      'title': title,
      'word_count': wordCount('$title $plain'),
      'char_count': charCount(plain),
    };
    if (n.isPrivate) {
      final v = vault;
      if (v == null) throw const AppException('err_vault_locked');
      row['cipher_text'] = v.encrypt(jsonEncode({'c': doc.toJson(), 'p': plain}));
      row['content'] = '';
      row['plain_text'] = '';
    } else {
      row['content'] = doc.toJson();
      row['plain_text'] = plain;
    }
    // Skip the write (and the sync) when nothing changed.
    if (n.title == title && (n.isPrivate ? false : n.content == row['content'])) {
      await clearDraft(id);
      return;
    }
    await store.save('notes', uid, row);
    await clearDraft(id);
    await reindexNote(id);
  }

  /// The body of a note (decrypted when private; throws when the vault is locked).
  OpenedNote open(Note n) {
    if (!n.isPrivate) return OpenedNote(n.content, n.plainText);
    final v = vault;
    if (v == null) throw const AppException('err_vault_locked');
    final s = v.decrypt(n.cipherText);
    if (s == AesGcmFieldCipher.unreadable) throw const AppException('err_vault_wrong');
    if (s.isEmpty) return const OpenedNote('', '');
    final m = jsonDecode(s) as Map<String, dynamic>;
    return OpenedNote(m['c']?.toString() ?? '', m['p']?.toString() ?? '');
  }

  /// Turns encryption of one note on or off (needs the unlocked vault).
  Future<void> setPrivate(String id, bool on) async {
    final n = await note(id);
    if (n == null || n.isPrivate == on) return;
    final v = vault;
    if (v == null) throw const AppException('err_vault_locked');
    if (on) {
      await store.save('notes', uid, {
        'id': id,
        'is_private': 1,
        'cipher_text': v.encrypt(jsonEncode({'c': n.content, 'p': n.plainText})),
        'content': '',
        'plain_text': '',
      });
    } else {
      final o = open(n);
      await store.save('notes', uid, {'id': id, 'is_private': 0, 'cipher_text': '', 'content': o.content, 'plain_text': o.plain});
    }
    await reindexNote(id);
  }

  Future<void> update(String id, Map<String, Object?> fields) async {
    await store.save('notes', uid, {'id': id, ...fields});
    if (fields.containsKey('notebook_id') || fields.containsKey('title') || fields.containsKey('trashed_at')) await reindexNote(id);
  }

  Future<void> setPinned(String id, bool v) => update(id, {'pinned': v ? 1 : 0});
  Future<void> setFavorite(String id, bool v) => update(id, {'favorite': v ? 1 : 0});
  Future<void> archive(String id, bool v) => update(id, TrashPolicy.archive(v));
  Future<void> trash(String id) => update(id, TrashPolicy.moveToTrash(DateTime.now()));
  Future<void> restore(String id) => update(id, TrashPolicy.restore());
  Future<void> move(String id, String? notebookId) => update(id, {'notebook_id': notebookId});

  Future<String> duplicate(String id, {String suffix = ''}) async {
    final n = await note(id);
    if (n == null) throw const AppException('err_not_found');
    final o = open(n);
    final copy = await createNote(type: n.type, notebookId: n.notebookId, title: '${n.title}$suffix', content: o.content, templateKey: n.templateKey);
    if (n.isPrivate) await setPrivate(copy, true);
    for (final t in await store.all('note_tags', uid, where: 'note_id = ?', args: [id])) {
      await store.save('note_tags', uid, {'note_id': copy, 'tag_id': t['tag_id']});
    }
    return copy;
  }

  /// Permanent delete (after the user confirmed): the note, its tag links and its files' rows.
  Future<void> deleteForever(String id) async {
    await store.delete('notes', id);
    await index.remove('note', id);
    await clearDraft(id);
  }

  /// Deletes trashed notes older than the retention period. Returns how many.
  Future<int> purgeExpiredTrash(NotesData d, DateTime now) async {
    var n = 0;
    for (final note in d.trash) {
      if (TrashPolicy.expired(note, now)) {
        await deleteForever(note.id);
        n++;
      }
    }
    return n;
  }

  // ------------------------------------------------------------------ drafts (crash safety)
  Future<void> writeDraft(String id, String title, String deltaJson) => store.db.insert('drafts', {
    'note_id': id,
    'user_id': uid,
    'title': title,
    'content': deltaJson,
    'saved_at': nowIso(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> clearDraft(String id) => store.db.delete('drafts', where: 'note_id = ?', whereArgs: [id]);

  /// Applies drafts left by a crash (the app was killed before the autosave reached the note).
  /// Returns the ids of recovered notes.
  Future<List<String>> recoverDrafts() async {
    final rows = await store.db.query('drafts', where: 'user_id = ?', whereArgs: [uid]);
    final out = <String>[];
    for (final r in rows) {
      final id = r['note_id'] as String;
      final n = await note(id);
      if (n == null) {
        await clearDraft(id);
        continue;
      }
      final draftAt = r['saved_at'] as String;
      final noteAt = n.r['updated_at'] as String? ?? '';
      if (draftAt.compareTo(noteAt) > 0) {
        try {
          await saveContent(id, r['title'] as String, r['content'] as String);
          out.add(id);
        } on AppException {
          continue; // private note while the vault is locked: keep the draft for later
        }
      } else {
        await clearDraft(id);
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ search index
  Future<void> reindexNote(String id) async {
    final r = await store.get('notes', id);
    if (r == null || r['deleted'] == 1) {
      await index.remove('note', id);
      return;
    }
    final n = Note(r);
    String folder = '';
    if (n.notebookId != null) {
      final nbs = (await store.all('notebooks', uid)).map(Notebook.new).toList();
      folder = FolderTree(nbs).path(n.notebookId, sep: ' ');
    }
    final tagIds = (await store.all('note_tags', uid, where: 'note_id = ?', args: [id])).map((t) => t['tag_id']).toSet();
    final tags = (await store.all('tags', uid)).where((t) => tagIds.contains(t['id'])).map((t) => t['name']).join(' ');
    final atts = await store.all('attachments', uid, where: 'note_id = ?', args: [id]);
    final voices = await store.all('voice_recordings', uid, where: 'note_id = ?', args: [id]);
    await index.put(
      'note',
      id,
      uid,
      title: n.title,
      body: n.isPrivate ? '' : n.plainText, // encrypted notes: title only
      folder: folder,
      tags: tags,
      files: atts.map((a) => '${a['title']} ${a['ocr_text']}').join(' '),
      voice: voices.map((v) => '${v['title']} ${v['description']} ${v['transcript']}').join(' '),
    );
  }

  Future<void> reindexVoice(String id) async {
    final r = await store.get('voice_recordings', id);
    if (r == null || r['deleted'] == 1) {
      await index.remove('voice', id);
    } else {
      await index.put('voice', id, uid, title: r['title'].toString(), body: r['description'].toString(), voice: r['transcript'].toString());
    }
    final noteId = r?['note_id'] as String?;
    if (noteId != null) await reindexNote(noteId);
  }

  /// Rebuilds the whole index (after a sync brought changes, or on first start).
  Future<void> reindexAll() async {
    await index.clear(uid);
    for (final r in await store.all('notes', uid)) {
      await reindexNote(r['id'] as String);
    }
    for (final r in await store.all('voice_recordings', uid)) {
      await index.put('voice', r['id'] as String, uid, title: r['title'].toString(), body: r['description'].toString(), voice: r['transcript'].toString());
    }
  }

  Future<List<SearchHit>> search(String q) => index.search(uid, q);

  // ------------------------------------------------------------------ notebooks / folders
  Future<String> saveNotebook({String? id, String? parentId, required String name, String? color, String? icon, String? description, bool? pinned, int? sortOrder}) async {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    final row = <String, Object?>{
      'id': ?id,
      'name': name.trim(),
      'color': ?color,
      'icon': ?icon,
      'description': ?description,
      'pinned': ?(pinned == null ? null : (pinned ? 1 : 0)),
      'sort_order': ?sortOrder,
    };
    if (id == null) {
      row['parent_id'] = parentId;
      if (sortOrder == null) {
        final sibs = await store.all('notebooks', uid, where: parentId == null ? 'parent_id IS NULL' : 'parent_id = ?', args: [?parentId]);
        row['sort_order'] = sibs.length;
      }
    }
    final out = await store.save('notebooks', uid, row);
    if (id != null) {
      for (final n in await store.all('notes', uid, where: 'notebook_id = ?', args: [id])) {
        await reindexNote(n['id'] as String);
      }
    }
    return out;
  }

  /// Moves a folder under another (or to the top level). Refuses to move into itself.
  Future<void> moveNotebook(String id, String? newParent) async {
    final tree = FolderTree((await store.all('notebooks', uid)).map(Notebook.new).toList());
    if (!tree.canMove(id, newParent)) throw const AppException('err_move_into_self');
    await store.save('notebooks', uid, {'id': id, 'parent_id': newParent, 'sort_order': tree.childrenOf(newParent).length});
  }

  Future<void> reorderNotebooks(List<Notebook> ordered) async {
    final m = FolderTree.reorder(ordered);
    for (final e in m.entries) {
      await store.save('notebooks', uid, {'id': e.key, 'sort_order': e.value}, notify: false);
    }
    store.onChange?.call('notebooks');
  }

  Future<void> deleteNotebook(String id) async {
    final affected = await store.all('notes', uid, where: 'notebook_id = ?', args: [id]);
    await store.delete('notebooks', id);
    for (final n in affected) {
      await reindexNote(n['id'] as String);
    }
  }

  // ------------------------------------------------------------------ tags
  Future<String> saveTag({String? id, required String name, String? color}) async {
    final nm = name.trim().replaceAll('#', '');
    if (nm.isEmpty) throw const AppException('err_name_required');
    final dup = await store.all('tags', uid, where: 'name = ? COLLATE NOCASE${id == null ? '' : ' AND id <> ?'}', args: [nm, ?id]);
    if (dup.isNotEmpty) {
      if (id == null) return dup.first['id'] as String; // same name: reuse it
      throw const AppException('err_tag_exists');
    }
    final out = await store.save('tags', uid, {'id': ?id, 'name': nm, 'color': ?color});
    if (id != null) {
      for (final nt in await store.all('note_tags', uid, where: 'tag_id = ?', args: [id])) {
        await reindexNote(nt['note_id'] as String);
      }
    }
    return out;
  }

  Future<void> deleteTag(String id) async {
    final links = await store.all('note_tags', uid, where: 'tag_id = ?', args: [id]);
    await store.delete('tags', id);
    for (final l in links) {
      await reindexNote(l['note_id'] as String);
    }
  }

  /// Makes the note's tags exactly [tagIds].
  Future<void> setNoteTags(String noteId, Set<String> tagIds) async {
    final cur = await store.all('note_tags', uid, where: 'note_id = ?', args: [noteId]);
    final have = {for (final r in cur) r['tag_id'] as String: r['id'] as String};
    for (final e in have.entries) {
      if (!tagIds.contains(e.key)) await store.delete('note_tags', e.value);
    }
    for (final t in tagIds) {
      if (!have.containsKey(t)) await store.save('note_tags', uid, {'note_id': noteId, 'tag_id': t});
    }
    await reindexNote(noteId);
  }

  // ------------------------------------------------------------------ templates
  Future<String> saveTemplate({String? id, required String name, required String type, required String content, String icon = 'description', String description = ''}) {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    return store.save('templates', uid, {'id': ?id, 'name': name.trim(), 'note_type': type, 'content': content, 'icon': icon, 'description': description});
  }

  // ------------------------------------------------------------------ journal
  Future<String> saveJournal({String? id, required DateTime date, String title = '', required String content, int? mood, String achievements = '', String thoughts = '', String goals = ''}) {
    final doc = DeltaDoc.parse(content);
    return store.save('journal_entries', uid, {
      'id': ?id,
      'entry_date': dateKey(date),
      'title': title,
      'content': doc.toJson(),
      'plain_text': doc.plainText,
      'mood': mood,
      'achievements': achievements,
      'thoughts': thoughts,
      'goals': goals,
    });
  }

  // ------------------------------------------------------------------ voice
  Future<void> saveVoice(String id, Map<String, Object?> fields) async {
    await store.save('voice_recordings', uid, {'id': id, ...fields});
    await reindexVoice(id);
  }

  Future<void> deleteVoiceRow(String id) async {
    final r = await store.get('voice_recordings', id);
    await store.delete('voice_recordings', id);
    await index.remove('voice', id);
    final noteId = r?['note_id'] as String?;
    if (noteId != null) await reindexNote(noteId);
  }

  // ------------------------------------------------------------------ profile / vault
  Future<Profile?> profile() async {
    final r = await store.get('profiles', uid);
    return r == null || r['deleted'] == 1 ? null : Profile(r);
  }

  /// Creates the private-notes vault with [passphrase] (once per account).
  Future<void> createVault(String passphrase) async {
    if (passphrase.length < 6) throw const AppException('err_passphrase_short');
    final p = await profile();
    if (p != null && p.hasVault) throw const AppException('err_vault_exists');
    final (salt, check, cipher) = NoteVault.create(passphrase);
    await store.save('profiles', uid, {'id': uid, 'vault_salt': salt, 'vault_check': check});
    vault = cipher;
  }

  /// Unlocks the vault. Returns false when the passphrase is wrong.
  Future<bool> unlockVault(String passphrase) async {
    final p = await profile();
    if (p == null || !p.hasVault) throw const AppException('err_vault_missing');
    final c = NoteVault.unlock(passphrase, p.vaultSalt, p.vaultCheck);
    if (c == null) return false;
    vault = c;
    return true;
  }

  void lockVault() => vault = null;

  // ------------------------------------------------------------------ backup
  /// Every live row of this user, table by table (private notes stay encrypted).
  Future<Map<String, List<Map<String, Object?>>>> dump() async => {
    for (final t in kTables) t.name: [for (final r in await store.all(t.name, uid)) Map<String, Object?>.from(r)..remove('dirty')..remove('user_id')],
  };

  /// Merges a backup: rows missing here, or newer in the backup, are written. Returns how many.
  Future<int> restoreBackup(Map<String, dynamic> data) async {
    var n = 0;
    for (final t in kTables) {
      final rows = data[t.name];
      if (rows is! List) continue;
      for (final raw in rows) {
        if (raw is! Map || raw['id'] == null) continue;
        final row = Map<String, Object?>.from(raw)..remove('user_id')..remove('dirty');
        if (t.name == 'profiles') row['id'] = uid;
        final cur = await store.get(t.name, row['id'] as String);
        if (cur != null && cur['user_id'] != uid) continue; // never write over another account's row
        final newer = cur == null || (row['updated_at']?.toString() ?? '').compareTo(cur['updated_at']?.toString() ?? '') > 0 || cur['deleted'] == 1;
        if (!newer) continue;
        row.remove('updated_at');
        row['deleted'] = 0;
        await store.save(t.name, uid, row, notify: false);
        n++;
      }
    }
    store.onChange?.call('*');
    await reindexAll();
    return n;
  }
}


import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_pro/core/errors/app_exception.dart';
import 'package:notes_pro/data/db/app_database.dart';
import 'package:notes_pro/data/db/local_store.dart';
import 'package:notes_pro/data/db/search_index.dart';
import 'package:notes_pro/data/repositories/notes_repository.dart';
import 'package:notes_pro/data/security/field_cipher.dart';
import 'package:notes_pro/domain/entities/entities.dart';
import 'package:notes_pro/domain/services/delta_doc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const uid = '11111111-1111-4111-8111-111111111111';

Future<(Database, NotesRepository)> open({FieldCipher? cipher, Database? reuse}) async {
  sqfliteFfiInit();
  final db = reuse ?? await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false));
  if (reuse == null) await AppDatabase.create(db);
  final index = SearchIndex(db);
  await index.init();
  return (db, NotesRepository(LocalStore(db, cipher: cipher), index, uid));
}

String doc(String text) => DeltaDoc.fromPlain(text).toJson();

void main() {
  group('autosave and crash recovery', () {
    test('a draft written before a crash is applied on the next start', () async {
      final (db, repo) = await open();
      final id = await repo.createNote(title: 'Lecture');
      await repo.saveContent(id, 'Lecture', doc('first line'));
      // the editor wrote its draft (300 ms) but the app died before the autosave (debounce)
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.writeDraft(id, 'Lecture 3', doc('first line\nsecond line typed just before the crash'));
      // "restart": a fresh repository on the same database file
      final (_, again) = await open(reuse: db);
      final recovered = await again.recoverDrafts();
      expect(recovered, [id]);
      final n = (await again.note(id))!;
      expect(n.title, 'Lecture 3');
      expect(n.plainText, contains('second line'));
      expect(await db.query('drafts'), isEmpty);
    });

    test('an older draft never overwrites a newer save', () async {
      final (db, repo) = await open();
      final id = await repo.createNote();
      await repo.writeDraft(id, 'old', doc('old draft'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.saveContent(id, 'new', doc('newer save'));
      await repo.writeDraft(id, 'old', doc('old draft')); // re-insert, but with an older stamp:
      await db.update('drafts', {'saved_at': '2000-01-01T00:00:00.000Z'});
      expect(await repo.recoverDrafts(), isEmpty);
      expect((await repo.note(id))!.title, 'new');
    });

    test('saving updates word and character counts, and skips no-op saves', () async {
      final (db, repo) = await open();
      final id = await repo.createNote();
      await repo.saveContent(id, 'مرحبا', doc('هذه ملاحظة قصيرة'));
      final n = (await repo.note(id))!;
      expect(n.r['word_count'], 4);
      expect(n.r['char_count'], 'هذه ملاحظة قصيرة'.length);
      final stamp = n.r['updated_at'];
      await repo.saveContent(id, 'مرحبا', doc('هذه ملاحظة قصيرة'));
      expect((await repo.note(id))!.r['updated_at'], stamp);
    });
  });

  group('full-text search (FTS5) including Arabic', () {
    test('finds words regardless of harakat / hamza, with prefixes, in titles, tags, folders and transcripts', () async {
      final (db, repo) = await open();
      expect(repo.index.mode, FtsMode.fts5);
      final nb = await repo.saveNotebook(name: 'الجامعة');
      final a = await repo.createNote(title: 'مَشروع التخرّج', content: doc('نناقش فكرة أسامة عن التطبيق'), notebookId: nb);
      final b = await repo.createNote(title: 'Shopping', content: doc('milk and bread'));
      final tag = await repo.saveTag(name: 'مهم');
      await repo.setNoteTags(b, {tag});
      Future<Set<String>> q(String s) async => (await repo.search(s)).map((h) => h.id).toSet();
      expect(await q('مشروع'), {a});
      expect(await q('اسامه'), {a}); // أسامة
      expect(await q('التطب'), {a}); // prefix
      expect(await q('الجامعه'), {a}); // folder name
      expect(await q('مهم'), {b}); // tag
      expect(await q('MILK'), {b});
      expect(await q('مشروع milk'), isEmpty); // every word must match
      final v = await repo.save('voice_recordings', {'title': 'تسجيل', 'transcript': 'محاضرة الشبكات العصبية'});
      await repo.reindexVoice(v);
      expect((await repo.search('العصبيه')).single.kind, 'voice');
      // edits and the trash keep the index right
      await repo.saveContent(a, 'عنوان آخر', doc('لا شيء'));
      expect(await q('مشروع'), isEmpty);
      await repo.deleteForever(b);
      expect(await q('milk'), isEmpty);
    });

    test('private notes are not searchable by their content', () async {
      final (_, repo) = await open();
      await repo.createVault('passphrase-1');
      final id = await repo.createNote(title: 'Bank', content: doc('pin 4455'));
      await repo.setPrivate(id, true);
      expect(await repo.search('4455'), isEmpty);
    });
  });

  group('private notes vault', () {
    test('encrypted at rest with the passphrase, readable only after unlocking', () async {
      final (db, repo) = await open();
      await repo.createVault('correct horse');
      final id = await repo.createNote(title: 'Diary', content: doc('سرّي جداً'));
      await repo.setPrivate(id, true);
      final raw = (await db.query('notes', where: 'id = ?', whereArgs: [id])).single;
      expect(raw['content'], '');
      expect(raw['plain_text'], '');
      expect(raw['cipher_text'].toString(), isNot(contains('سرّي')));
      expect(repo.open((await repo.note(id))!).plain, contains('سرّي'));
      repo.lockVault();
      expect(() => repo.open(Note(raw)), throwsA(isA<AppException>()));
      expect(await repo.unlockVault('wrong'), isFalse);
      expect(await repo.unlockVault('correct horse'), isTrue);
      await repo.saveContent(id, 'Diary', doc('تعديل جديد'));
      expect(repo.open((await repo.note(id))!).plain, contains('تعديل'));
      await repo.setPrivate(id, false);
      expect((await repo.note(id))!.plainText, contains('تعديل'));
    });
  });

  group('notebooks, tags, trash', () {
    test('deleting a notebook removes its sub-folders and keeps the notes', () async {
      final (_, repo) = await open();
      final w = await repo.saveNotebook(name: 'Work');
      final p = await repo.saveNotebook(name: 'Projects', parentId: w);
      final n = await repo.createNote(notebookId: p, title: 'keep me');
      await expectLater(repo.moveNotebook(w, p), throwsA(isA<AppException>()));
      await repo.deleteNotebook(w);
      final d = await repo.load();
      expect(d.notebooks, isEmpty);
      expect(d.noteById[n]!.notebookId, isNull);
      expect(d.active.single.id, n);
    });

    test('trash, restore, expiry purge, duplicate', () async {
      final (db, repo) = await open();
      final a = await repo.createNote(title: 'A', content: doc('x'));
      await repo.setPinned(a, true);
      await repo.trash(a);
      var d = await repo.load();
      expect(d.trash.single.pinned, isFalse);
      await repo.restore(a);
      d = await repo.load();
      expect(d.active.single.id, a);
      final copy = await repo.duplicate(a, suffix: ' (copy)');
      expect((await repo.note(copy))!.title, 'A (copy)');
      await repo.trash(a);
      await db.update('notes', {'trashed_at': '2026-01-01T00:00:00.000Z'}, where: 'id = ?', whereArgs: [a]);
      expect(await repo.purgeExpiredTrash(await repo.load(), DateTime.utc(2026, 11, 3)), 1);
      expect(await repo.note(a), isNull);
    });

    test('tags: no duplicates, note links replaced', () async {
      final (_, repo) = await open();
      final t1 = await repo.saveTag(name: 'study');
      expect(await repo.saveTag(name: '#Study'), t1); // same name, any case: reused, not duplicated
      final t2 = await repo.saveTag(name: 'exam');
    await expectLater(repo.saveTag(id: t2, name: 'STUDY'), throwsA(isA<AppException>())); // renaming onto another tag
      final n = await repo.createNote();
      await repo.setNoteTags(n, {t1, t2});
      await repo.setNoteTags(n, {t2});
      final d = await repo.load();
      expect(d.tagsOfNote[n], {t2});
      expect(d.tagCount(t1), 0);
    });
  });

  test('backup dump and restore into another device', () async {
    final key = AesGcmFieldCipher.newKey();
    final (_, a) = await open(cipher: AesGcmFieldCipher(key));
    await a.createNote(title: 'One', content: doc('first'));
    await a.saveJournal(date: DateTime(2026, 11, 3), content: doc('يوم جميل'), mood: 4);
    final dump = jsonDecode(jsonEncode(await a.dump())) as Map<String, dynamic>;
    final (_, b) = await open(cipher: AesGcmFieldCipher(AesGcmFieldCipher.newKey()));
    expect(await b.restoreBackup(dump), greaterThanOrEqualTo(2));
    final d = await b.load();
    expect(d.active.single.title, 'One');
    expect(d.journal.single.plainText, 'يوم جميل');
    expect(await b.restoreBackup(dump), 0); // idempotent
  });

  test('backup encryption', () {
    final sealed = BackupCrypto.seal('{"format":"notes_pro_backup"}', 'correct horse');
    expect(sealed, isNot(contains('notes_pro_backup')));
    expect(BackupCrypto.open(sealed, 'correct horse'), '{"format":"notes_pro_backup"}');
    expect(BackupCrypto.open(sealed, 'wrong'), isNull);
    final c = AesGcmFieldCipher(AesGcmFieldCipher.newKey());
    final data = Uint8List.fromList(List<int>.generate(3000, (i) => i % 251));
    expect(c.decryptBytes(c.encryptBytes(data)), data);
  });
}

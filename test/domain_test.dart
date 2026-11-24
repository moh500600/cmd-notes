import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_pro/core/utils/text_tools.dart';
import 'package:notes_pro/domain/entities/entities.dart';
import 'package:notes_pro/domain/services/delta_doc.dart';
import 'package:notes_pro/domain/services/folder_tree.dart';
import 'package:notes_pro/domain/services/note_format.dart';
import 'package:notes_pro/domain/services/notes_data.dart';
import 'package:notes_pro/domain/services/reminders.dart';
import 'package:notes_pro/domain/services/share_roles.dart';
import 'package:notes_pro/domain/services/templates.dart';
import 'package:notes_pro/domain/services/trash.dart';

Notebook nb(String id, String name, {String? parent, int order = 0}) => Notebook({'id': id, 'name': name, 'parent_id': parent, 'sort_order': order, 'deleted': 0});
Note note(String id, {String title = '', String? trashedAt, int archived = 0, int pinned = 0, String? notebook, String updated = '2026-11-01T10:00:00.000Z'}) => Note({
  'id': id,
  'title': title,
  'content': DeltaDoc.fromPlain('body $id').toJson(),
  'plain_text': 'body $id',
  'note_type': 'text',
  'trashed_at': trashedAt,
  'archived': archived,
  'pinned': pinned,
  'favorite': 0,
  'notebook_id': notebook,
  'created_at': '2026-10-01T10:00:00.000Z',
  'updated_at': updated,
  'deleted': 0,
});

void main() {
  group('folder tree (unlimited nesting)', () {
    final all = [nb('w', 'Work'), nb('p', 'Projects', parent: 'w'), nb('y', '2026', parent: 'p'), nb('h', 'Home', order: 1), nb('x', 'Loop', parent: 'x')];
    final t = FolderTree(all);
    test('builds roots, depth and a depth-first list', () {
      final flat = t.flat();
      expect(flat.map((e) => e.$1.id).toList().sublist(0, 3), ['w', 'p', 'y']);
      expect(flat.firstWhere((e) => e.$1.id == 'y').$2, 2);
      expect(t.roots.map((n) => n.id), containsAll(['w', 'h']));
    });
    test('descendants and moving rules', () {
      expect(t.descendantsOf('w'), {'w', 'p', 'y'});
      expect(t.canMove('w', 'y'), isFalse); // into its own sub-folder
      expect(t.canMove('w', 'w'), isFalse);
      expect(t.canMove('y', 'h'), isTrue);
      expect(t.canMove('y', null), isTrue);
    });
    test('path and reorder', () {
      expect(t.path('y'), 'Work › Projects › 2026');
      expect(FolderTree.reorder([all[3], all[0]]), {'h': 0, 'w': 1});
    });
    test('a self-parented folder does not loop forever', () {
      expect(() => t.build(), returnsNormally);
      expect(t.path('x'), isNotEmpty);
    });
  });

  group('trash and archive', () {
    final now = DateTime.utc(2026, 11, 3);
    test('moving to trash unpins and stamps the time; restore clears it', () {
      final m = TrashPolicy.moveToTrash(now);
      expect(m['pinned'], 0);
      expect(m['trashed_at'], isNotNull);
      expect(TrashPolicy.restore(), {'trashed_at': null});
    });
    test('30-day retention', () {
      final n = note('a', trashedAt: '2026-10-20T00:00:00.000Z');
      expect(TrashPolicy.daysLeft(n, now), 16);
      expect(TrashPolicy.expired(n, now), isFalse);
      final old = note('b', trashedAt: '2026-10-01T00:00:00.000Z');
      expect(TrashPolicy.expired(old, now), isTrue);
      expect(TrashPolicy.daysLeft(old, now), 0);
    });
    test('buckets and lists', () {
      final d = NotesData(uid: 'u', notes: [note('a', pinned: 1), note('b', archived: 1), note('c', trashedAt: '2026-11-01T00:00:00.000Z'), note('d', notebook: 'w')], notebooks: [nb('w', 'Work')]);
      expect(d.active.map((n) => n.id), containsAll(['a', 'd']));
      expect(d.archived.single.id, 'b');
      expect(d.trash.single.id, 'c');
      expect(d.pinned.single.id, 'a');
      expect(bucketOf(d.noteById['c']!), NoteBucket.trash);
      expect(d.inNotebook('w').single.id, 'd');
    });
  });

  group('Arabic-aware search text', () {
    test('normalises harakat, hamza forms, taa marbuta and alef maqsura', () {
      expect(normalizeForSearch('مَشْرُوع'), normalizeForSearch('مشروع'));
      expect(normalizeForSearch('أسامة'), normalizeForSearch('اسامه'));
      expect(normalizeForSearch('إيمان'), normalizeForSearch('ايمان'));
      expect(normalizeForSearch('مستشفى'), normalizeForSearch('مستشفي'));
      expect(normalizeForSearch('Hello WORLD'), 'hello world');
    });
    test('fts query is a prefix match of every word, injection-safe', () {
      expect(ftsQuery('مشروع تطبيق'), '"مشروع"* "تطبيق"*');
      expect(ftsQuery('a"b OR c'), isNot(contains('OR c"')));
      expect(ftsQuery('   '), isNull);
    });
    test('counts and direction', () {
      expect(wordCount('مرحبا بك في التطبيق hello'), 5);
      expect(charCount('abc\nde'), 5);
      expect(isRtlText('ملاحظة جديدة'), isTrue);
      expect(isRtlText('new note'), isFalse);
    });
  });

  group('rich text document', () {
    test('checklists, attachments and plain text from the delta', () {
      final doc = (DeltaBuilder()
            ..h(1, 'Title')
            ..check('one', done: true)
            ..check('two')
            ..table([
              ['a', 'b'],
              ['1', '2'],
            ])
            ..raw(const Block([], {}, embedType: Embeds.image, embedData: '{"id":"img1","name":"p.png"}')))
          .build();
      expect(doc.checklist, (1, 2));
      expect(doc.attachmentIds, {'img1'});
      expect(doc.plainText, contains('one'));
      expect(doc.plainText, contains('a | b'));
      final back = DeltaDoc.parse(doc.toJson());
      expect(back.blocks.length, doc.blocks.length);
    });
    test('garbage content does not crash', () {
      expect(DeltaDoc.parse('not json').plainText, 'not json');
      expect(DeltaDoc.parse(null).plainText, '');
    });
  });

  group('export / import formats', () {
    final doc = (DeltaBuilder()
          ..h(2, 'الأفكار')
          ..p('نص **عادي** مع English')
          ..bullet('عنصر')
          ..ordered('أول')
          ..check('مهمة', done: true)
          ..quote('اقتباس')
          ..code('print(1);')
          ..table([
            ['الاسم', 'القيمة'],
            ['x', '1'],
          ]))
        .build();
    test('TXT', () {
      final t = NoteFormat.toTxt('ملاحظتي', doc);
      expect(t, startsWith('ملاحظتي'));
      expect(t, contains('• عنصر'));
      expect(t, contains('☑ مهمة'));
    });
    test('Markdown round trip', () {
      final md = NoteFormat.toMarkdown('ملاحظتي', doc);
      expect(md, startsWith('# ملاحظتي'));
      expect(md, contains('- [x] مهمة'));
      expect(md, contains('| الاسم | القيمة |'));
      final (title, back) = NoteFormat.fromMarkdown(md);
      expect(title, 'ملاحظتي');
      expect(back.checklist, (1, 1));
      expect(back.blocks.any((b) => b.embedType == Embeds.table), isTrue);
      expect(back.blocks.any((b) => b.codeBlock), isTrue);
    });
    test('HTML is RTL for Arabic and imports back', () {
      final html = NoteFormat.toHtml('ملاحظتي', doc, rtl: true);
      expect(html, contains('dir="rtl"'));
      expect(html, contains('<table'));
      final (title, back) = NoteFormat.fromHtml(html);
      expect(title, 'ملاحظتي');
      expect(back.plainText, contains('عنصر'));
      expect(back.blocks.any((b) => b.list == 'checked'), isTrue);
    });
    test('DOCX is a valid Word package with right-to-left paragraphs', () {
      final bytes = NoteFormat.toDocx('ملاحظتي', doc);
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).toSet();
      expect(names, containsAll(['[Content_Types].xml', 'word/document.xml', '_rels/.rels']));
      final xml = utf8.decode(zip.files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);
      expect(xml, contains('<w:bidi/>'));
      expect(xml, contains('ملاحظتي'));
      expect(xml, contains('<w:tbl>'));
    });
    test('import picks the parser by extension', () {
      expect(NoteFormat.import('a.txt', 'Title\nline').$1, 'Title');
      expect(NoteFormat.import('a.md', '# T\n- x').$2.blocks.first.list, 'bullet');
      expect(NoteFormat.import('a.html', '<h1>T</h1><p>x</p>').$1, 'T');
    });
  });

  group('sharing roles', () {
    test('what each role allows', () {
      expect(ShareRole.view.canComment, isFalse);
      expect(ShareRole.view.canEdit, isFalse);
      expect(ShareRole.comment.canComment, isTrue);
      expect(ShareRole.comment.canEdit, isFalse);
      expect(ShareRole.edit.canEdit, isTrue);
      expect(ShareRole.edit.canManage, isFalse); // never delete / re-share
    });
    test('strongest of a direct and a notebook share', () {
      expect(strongest([ShareRole.view, ShareRole.edit, ShareRole.comment]), ShareRole.edit);
      expect(strongest(const []), ShareRole.view);
      expect(roleOf('bogus'), ShareRole.view);
    });
    test('emails', () {
      expect(normalizeShareEmail('  Sara@Example.COM '), 'sara@example.com');
      expect(normalizeShareEmail('nope'), isNull);
    });
  });

  group('templates', () {
    test('11 built-in templates, valid in both languages', () {
      expect(kTemplateLibrary.length, 11);
      for (final t in kTemplateLibrary) {
        for (final ar in [true, false]) {
          expect(DeltaDoc.parse(t.body(ar)).plainText.trim(), isNotEmpty, reason: t.key);
          expect(t.name(ar), isNotEmpty);
        }
        expect(kNoteTypes, contains(t.type));
      }
    });
    test('every note type has a starting body', () {
      expect(kNoteTypes.length, 11);
      for (final t in kNoteTypes) {
        expect(() => DeltaDoc.parse(defaultBodyFor(t, true)), returnsNormally);
      }
      expect(DeltaDoc.parse(defaultBodyFor('todo', false)).checklist.$2, greaterThan(0));
    });
  });

  test('reminders: future dates only, private titles hidden, stable ids', () {
    final now = DateTime.utc(2026, 11, 3, 8);
    final n = Note({...note('a', title: 'Exam').r, 'remind_at': '2026-11-04T08:00:00.000Z', 'review_at': '2026-11-01T08:00:00.000Z'});
    final p = Note({...note('b', title: 'Secret').r, 'is_private': 1, 'event_at': '2026-11-05T08:00:00.000Z'});
    final d = NotesData(uid: 'u', notes: [n, p]);
    final plan = planReminders(d, const ReminderPrefs(eventLeadMin: 30), now);
    expect(plan.where((r) => r.noteId == 'a').length, 1); // the past review is skipped
    final ev = plan.firstWhere((r) => r.noteId == 'b');
    expect(ev.title, ''); // private
    expect(ev.when.isAtSameMomentAs(DateTime.utc(2026, 11, 5, 7, 30)), isTrue);
    expect(alertId('a:remind'), alertId('a:remind'));
    expect(planReminders(d, const ReminderPrefs(enabled: false), now), isEmpty);
  });
}

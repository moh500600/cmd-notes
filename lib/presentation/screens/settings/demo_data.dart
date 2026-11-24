import 'dart:convert';

import '../../../data/repositories/notes_repository.dart';
import '../../../domain/services/delta_doc.dart';
import '../../../domain/services/templates.dart';

/// Sample notebooks, folders, tags, notes and journal pages — to try the app (and for screenshots).
Future<void> loadDemoData(NotesRepository repo, {required bool ar}) async {
  String t(String a, String e) => ar ? a : e;
  final now = DateTime.now();
  final uni = await repo.saveNotebook(name: t('الجامعة', 'University'), color: '#4F46E5', icon: 'school', description: t('محاضرات ومشاريع', 'Lectures and projects'), pinned: true);
  final ai = await repo.saveNotebook(parentId: uni, name: t('الذكاء الاصطناعي', 'AI course'), color: '#7C3AED', icon: 'science');
  final work = await repo.saveNotebook(name: t('العمل', 'Work'), color: '#0F766E', icon: 'work');
  final proj = await repo.saveNotebook(parentId: work, name: t('مشروع التطبيق', 'App project'), color: '#0EA5E9', icon: 'code');
  final home = await repo.saveNotebook(name: t('شخصي', 'Personal'), color: '#DB2777', icon: 'home');

  final tUrgent = await repo.saveTag(name: t('مهم', 'important'), color: '#E11D48');
  final tIdeas = await repo.saveTag(name: t('أفكار', 'ideas'), color: '#D97706');
  final tStudy = await repo.saveTag(name: t('مذاكرة', 'study'), color: '#4F46E5');
  final tWeekly = await repo.saveTag(name: t('أسبوعي', 'weekly'), color: '#16A34A');

  Future<String> note(String type, String title, Object body, {String? nb, Set<String> tags = const {}, bool pin = false, bool fav = false, DateTime? event, String color = ''}) async {
    final json = body is DeltaBuilder ? body.json() : body as String;
    final id = await repo.createNote(type: type, notebookId: nb, title: title, content: json, eventAt: event);
    await repo.saveContent(id, title, json);
    if (pin) await repo.setPinned(id, true);
    if (fav) await repo.setFavorite(id, true);
    if (color.isNotEmpty) await repo.update(id, {'color': color});
    if (tags.isNotEmpty) await repo.setNoteTags(id, tags);
    return id;
  }

  await note(
    'study',
    t('محاضرة الشبكات العصبية', 'Neural networks lecture'),
    DeltaBuilder()
      ..h(2, t('الأفكار الرئيسية', 'Key ideas'))
      ..bullet(t('الخلية العصبية: مدخلات × أوزان + انحياز', 'Neuron: inputs × weights + bias'))
      ..bullet(t('دالة التفعيل ReLU و Sigmoid', 'Activation functions: ReLU and Sigmoid'))
      ..bullet(t('الانتشار العكسي لتحديث الأوزان', 'Backpropagation updates the weights'))
      ..h(2, t('أسئلة للمراجعة', 'Review questions'))
      ..check(t('لماذا نحتاج دالة تفعيل غير خطية؟', 'Why do we need a non-linear activation?'))
      ..check(t('ما الفرق بين التدريب والاختبار؟', 'Training vs. test set?'), done: true)
      ..table([
        [t('المفهوم', 'Concept'), t('المعنى', 'Meaning')],
        ['Epoch', t('مرور كامل على البيانات', 'One full pass over the data')],
        ['Batch', t('مجموعة أمثلة في خطوة واحدة', 'Examples per step')],
      ]),
    nb: ai,
    tags: {tStudy, tUrgent},
    pin: true,
    fav: true,
  );
  await note(
    'meeting',
    t('اجتماع فريق التطبيق', 'App team meeting'),
    DeltaBuilder()
      ..p(t('الحضور: محمد، سارة، أحمد', 'Attendees: Mohammad, Sara, Ahmed'))
      ..h(2, t('القرارات', 'Decisions'))
      ..ordered(t('إطلاق النسخة التجريبية يوم الخميس', 'Ship the beta on Thursday'))
      ..ordered(t('اعتماد Supabase للمزامنة', 'Use Supabase for sync'))
      ..h(2, t('المهام', 'Action items'))
      ..check(t('سارة: تصميم شاشة البحث', 'Sara: design the search screen'))
      ..check(t('أحمد: اختبار المزامنة دون اتصال', 'Ahmed: test offline sync')),
    nb: proj,
    tags: {tWeekly},
    event: DateTime(now.year, now.month, now.day + 2, 10),
  );
  await note(
    'todo',
    t('مهام الأسبوع', 'This week'),
    DeltaBuilder()
      ..check(t('تسليم تقرير المختبر', 'Submit the lab report'), done: true)
      ..check(t('مراجعة الفصل الرابع', 'Review chapter 4'))
      ..check(t('حجز موعد طبيب الأسنان', 'Book the dentist'))
      ..check(t('شراء هدية لأمي', 'Buy a gift for mom')),
    tags: {tWeekly, tUrgent},
    pin: true,
    color: '#16A34A',
  );
  await note(
    'idea',
    t('فكرة: تطبيق لتبادل الكتب', 'Idea: a book-swap app'),
    DeltaBuilder()
      ..p(t('منصة يتبادل فيها الطلاب الكتب المستعملة داخل الجامعة.', 'A place where students swap used books on campus.'))
      ..quote(t('أفضل الأفكار تحل مشكلة تعيشها كل يوم.', 'The best ideas solve a problem you live every day.'))
      ..bullet(t('تسجيل بالبريد الجامعي', 'Sign up with the university email'))
      ..bullet(t('خريطة نقاط التسليم', 'Map of hand-over spots')),
    nb: home,
    tags: {tIdeas},
    fav: true,
  );
  await note(
    'shopping',
    t('قائمة التسوق', 'Shopping list'),
    DeltaBuilder()
      ..check(t('حليب', 'Milk'))
      ..check(t('خبز أسمر', 'Brown bread'), done: true)
      ..check(t('تمر', 'Dates'))
      ..check(t('قهوة', 'Coffee')),
    nb: home,
  );
  await note(
    'code',
    t('مقتطف: دالة البحث', 'Snippet: search function'),
    DeltaBuilder()
      ..p(t('تطبيع النص العربي قبل البحث:', 'Normalise Arabic before searching:'))
      ..code("String norm(String s) => s\n  .replaceAll(RegExp('[أإآ]'), 'ا')\n  .replaceAll('ة', 'ه');"),
    nb: proj,
  );
  await note('work', t('خطة الربع القادم', 'Next quarter plan'), builtinTemplate('project')!.body(ar), nb: work, event: DateTime(now.year, now.month, now.day + 6, 13));
  await note('text', t('اقتباسات أحبها', 'Quotes I like'), DeltaBuilder()..quote(t('العلم في الصغر كالنقش على الحجر', 'Learning young is carving in stone'))..p('Stay hungry, stay foolish.'), tags: {tIdeas});

  for (var i = 0; i < 4; i++) {
    final day = now.subtract(Duration(days: i * 2));
    await repo.saveJournal(
      date: day,
      title: [t('يوم منتج', 'A productive day'), t('هادئ', 'Calm'), t('مرهق قليلاً', 'A bit tiring'), t('مع العائلة', 'With family')][i],
      content: DeltaDoc.fromPlain(t('أنهيت معظم المهام ومشيت نصف ساعة مساءً.', 'Finished most tasks and walked for half an hour.')).toJson(),
      mood: [4, 3, 1, 4][i],
      achievements: t('تسليم التقرير', 'Report submitted'),
      goals: t('النوم مبكراً', 'Sleep early'),
    );
  }
  await repo.saveTemplate(
    name: t('مراجعة كتاب', 'Book review'),
    type: 'study',
    icon: 'auto_stories',
    content: jsonEncode((DeltaBuilder()
          ..h(2, t('الكتاب', 'Book'))
          ..p('')
          ..h(2, t('أهم الأفكار', 'Key ideas'))
          ..bullet('')
          ..h(2, t('تقييمي', 'My rating'))
          ..p('⭐⭐⭐⭐'))
        .build()
        .ops),
  );
}

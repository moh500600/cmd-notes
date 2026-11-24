import 'delta_doc.dart';

/// A built-in template (spec §13 library + one default per note type, spec §6).
class BuiltinTemplate {
  final String key;
  final String type; // note type the template creates
  final String icon;
  final String Function(bool ar) name;
  final String Function(bool ar) body; // delta JSON
  const BuiltinTemplate(this.key, this.type, this.icon, this.name, this.body);
}

String _d(bool ar, void Function(DeltaBuilder b) f) {
  final b = DeltaBuilder();
  f(b);
  return b.json();
}

String _t(bool ar, String a, String e) => ar ? a : e;

/// The library (11 templates the spec lists).
final kTemplateLibrary = <BuiltinTemplate>[
  BuiltinTemplate('meeting', 'meeting', 'groups', (ar) => _t(ar, 'اجتماع', 'Meeting'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'اجتماع: ', 'Meeting: '));
    b.p(_t(ar, 'التاريخ والوقت: ', 'Date & time: ')).p(_t(ar, 'المكان / الرابط: ', 'Place / link: '));
    b.h(2, _t(ar, 'الحضور', 'Attendees')).bullet('');
    b.h(2, _t(ar, 'جدول الأعمال', 'Agenda')).ordered('');
    b.h(2, _t(ar, 'النقاش والملاحظات', 'Discussion')).p('');
    b.h(2, _t(ar, 'القرارات', 'Decisions')).bullet('');
    b.h(2, _t(ar, 'المهام والمسؤولون', 'Action items')).check('');
    b.table([
      [_t(ar, 'المهمة', 'Task'), _t(ar, 'المسؤول', 'Owner'), _t(ar, 'الموعد', 'Due')],
      ['', '', ''],
    ]);
  })),
  BuiltinTemplate('lecture', 'study', 'school', (ar) => _t(ar, 'محاضرة', 'Lecture'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'محاضرة: ', 'Lecture: '));
    b.p(_t(ar, 'المادة: ', 'Course: ')).p(_t(ar, 'الدكتور: ', 'Lecturer: ')).p(_t(ar, 'التاريخ: ', 'Date: '));
    b.h(2, _t(ar, 'الأفكار الرئيسية', 'Key ideas')).bullet('');
    b.h(2, _t(ar, 'الشرح والتفاصيل', 'Notes')).p('');
    b.h(2, _t(ar, 'تعريفات ومصطلحات', 'Terms')).bullet('');
    b.h(2, _t(ar, 'أسئلة للمراجعة', 'Review questions')).ordered('');
    b.h(2, _t(ar, 'الملخص', 'Summary')).quote('');
  })),
  BuiltinTemplate('project', 'idea', 'rocket_launch', (ar) => _t(ar, 'مشروع', 'Project'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'مشروع: ', 'Project: '));
    b.h(2, _t(ar, 'الهدف', 'Goal')).p('');
    b.h(2, _t(ar, 'النطاق', 'Scope')).bullet('');
    b.h(2, _t(ar, 'المراحل', 'Milestones'));
    b.table([
      [_t(ar, 'المرحلة', 'Milestone'), _t(ar, 'الموعد', 'Due'), _t(ar, 'الحالة', 'Status')],
      ['', '', ''],
    ]);
    b.h(2, _t(ar, 'المهام', 'Tasks')).check('');
    b.h(2, _t(ar, 'المخاطر', 'Risks')).bullet('');
    b.h(2, _t(ar, 'الموارد والروابط', 'Resources')).bullet('');
  })),
  BuiltinTemplate('daily', 'personal', 'today', (ar) => _t(ar, 'تخطيط يومي', 'Daily plan'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'خطة اليوم', 'Today\'s plan'));
    b.h(2, _t(ar, 'أهم 3 مهام', 'Top 3')).check('').check('').check('');
    b.h(2, _t(ar, 'الجدول', 'Schedule'));
    b.table([
      [_t(ar, 'الوقت', 'Time'), _t(ar, 'النشاط', 'Activity')],
      ['08:00', ''],
      ['12:00', ''],
      ['16:00', ''],
    ]);
    b.h(2, _t(ar, 'ملاحظات', 'Notes')).p('');
    b.h(2, _t(ar, 'امتنان', 'Gratitude')).bullet('');
  })),
  BuiltinTemplate('weekly', 'personal', 'date_range', (ar) => _t(ar, 'تخطيط أسبوعي', 'Weekly plan'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'خطة الأسبوع', 'Week plan'));
    b.h(2, _t(ar, 'أهداف الأسبوع', 'Goals')).check('').check('');
    for (final d in ar ? ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'] : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']) {
      b.h(3, d).check('');
    }
    b.h(2, _t(ar, 'مراجعة نهاية الأسبوع', 'Weekly review')).p('');
  })),
  BuiltinTemplate('monthly', 'personal', 'calendar_month', (ar) => _t(ar, 'تخطيط شهري', 'Monthly plan'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'خطة الشهر', 'Month plan'));
    b.h(2, _t(ar, 'الأهداف', 'Goals')).ordered('');
    b.h(2, _t(ar, 'المواعيد المهمة', 'Key dates'));
    b.table([
      [_t(ar, 'التاريخ', 'Date'), _t(ar, 'الحدث', 'Event')],
      ['', ''],
    ]);
    b.h(2, _t(ar, 'العادات', 'Habits')).check('');
    b.h(2, _t(ar, 'الميزانية', 'Budget')).p('');
    b.h(2, _t(ar, 'المراجعة', 'Review')).p('');
  })),
  BuiltinTemplate('journal', 'journal', 'auto_stories', (ar) => _t(ar, 'يوميات', 'Journal'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'يومياتي', 'My day'));
    b.p(_t(ar, 'المزاج: ', 'Mood: '));
    b.h(2, _t(ar, 'ماذا حدث اليوم؟', 'What happened today?')).p('');
    b.h(2, _t(ar, 'إنجازات اليوم', 'Wins')).bullet('');
    b.h(2, _t(ar, 'أفكار', 'Thoughts')).p('');
    b.h(2, _t(ar, 'أهداف الغد', 'Tomorrow')).check('');
  })),
  BuiltinTemplate('research', 'study', 'science', (ar) => _t(ar, 'بحث علمي', 'Research'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'عنوان البحث', 'Research title'));
    b.h(2, _t(ar, 'المشكلة / السؤال', 'Problem / question')).p('');
    b.h(2, _t(ar, 'الفرضيات', 'Hypotheses')).ordered('');
    b.h(2, _t(ar, 'الدراسات السابقة', 'Literature')).bullet('');
    b.h(2, _t(ar, 'المنهجية', 'Method')).p('');
    b.h(2, _t(ar, 'النتائج', 'Results')).p('');
    b.h(2, _t(ar, 'الخلاصة', 'Conclusion')).p('');
    b.h(2, _t(ar, 'المراجع', 'References')).ordered('');
  })),
  BuiltinTemplate('todo', 'todo', 'checklist', (ar) => _t(ar, 'قائمة مهام', 'To-do list'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'المهام', 'Tasks'));
    b.h(3, _t(ar, 'عاجل', 'Urgent')).check('');
    b.h(3, _t(ar, 'مهم', 'Important')).check('');
    b.h(3, _t(ar, 'لاحقاً', 'Later')).check('');
  })),
  BuiltinTemplate('ideas', 'idea', 'lightbulb', (ar) => _t(ar, 'أفكار', 'Ideas'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'أفكار', 'Ideas'));
    b.h(2, _t(ar, 'الفكرة', 'The idea')).p('');
    b.h(2, _t(ar, 'لماذا؟', 'Why?')).p('');
    b.h(2, _t(ar, 'المزايا', 'Pros')).bullet('');
    b.h(2, _t(ar, 'التحديات', 'Challenges')).bullet('');
    b.h(2, _t(ar, 'الخطوة التالية', 'Next step')).check('');
  })),
  BuiltinTemplate('goals', 'personal', 'flag', (ar) => _t(ar, 'متابعة أهداف', 'Goal tracker'), (ar) => _d(ar, (b) {
    b.h(1, _t(ar, 'أهدافي', 'My goals'));
    b.table([
      [_t(ar, 'الهدف', 'Goal'), _t(ar, 'الموعد', 'Deadline'), _t(ar, 'التقدم', 'Progress')],
      ['', '', '0%'],
    ]);
    b.h(2, _t(ar, 'الخطوات', 'Steps')).check('');
    b.h(2, _t(ar, 'العوائق', 'Obstacles')).bullet('');
    b.h(2, _t(ar, 'مراجعة', 'Review')).p('');
  })),
];

/// Default body for each note type when the user has not chosen their own template.
String defaultBodyFor(String type, bool ar) {
  String key = switch (type) {
    'meeting' => 'meeting',
    'study' => 'lecture',
    'journal' => 'journal',
    'idea' => 'ideas',
    'todo' => 'todo',
    _ => '',
  };
  if (key.isNotEmpty) return kTemplateLibrary.firstWhere((t) => t.key == key).body(ar);
  final b = DeltaBuilder();
  switch (type) {
    case 'shopping':
      b.h(2, _t(ar, 'قائمة التسوق', 'Shopping list')).check('').check('').check('');
    case 'code':
      b.h(2, _t(ar, 'الوصف', 'Description')).p('').h(2, _t(ar, 'الكود', 'Code')).code('// ...').h(2, _t(ar, 'ملاحظات', 'Notes')).bullet('');
    case 'work':
      b.h(2, _t(ar, 'الموضوع', 'Topic')).p('').h(2, _t(ar, 'التفاصيل', 'Details')).p('').h(2, _t(ar, 'المتابعة', 'Follow-up')).check('');
    case 'personal':
      b.p('');
    case 'voice':
      b.h(2, _t(ar, 'تسجيل صوتي', 'Voice note')).p('');
    default:
      b.p('');
  }
  return b.json();
}

BuiltinTemplate? builtinTemplate(String key) {
  for (final t in kTemplateLibrary) {
    if (t.key == key) return t;
  }
  return null;
}

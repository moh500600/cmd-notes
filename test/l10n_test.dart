import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_pro/core/l10n/strings.dart';
import 'package:notes_pro/domain/entities/entities.dart';

/// Every literal key passed to tr('…') in lib/ exists in both languages with the same
/// {placeholders}; every value used in a dynamic key has a label.
void main() {
  test('every string has Arabic and English with matching placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in kStrings.entries) {
      expect(e.value.length, 2, reason: e.key);
      expect(e.value[0].trim(), isNotEmpty, reason: '${e.key} ar');
      expect(e.value[1].trim(), isNotEmpty, reason: '${e.key} en');
      final a = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      final b = ph.allMatches(e.value[1]).map((m) => m[1]).toSet();
      expect(a, b, reason: 'placeholders of ${e.key}');
    }
  });

  test('every literal tr key used in lib/ is translated', () {
    final re = RegExp(r"""\btr\(\s*'([^'$]+)'""");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        if (!kStrings.containsKey(m[1])) missing.add('${m[1]} (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });

  test('every dynamic key has a label', () {
    final families = {
      'type_': kNoteTypes,
      'quick_': ['note', 'todo', 'voice', 'image', 'document', 'journal'],
      'role_': ['view', 'comment', 'edit'],
      'sort_': ['updated', 'created', 'title'],
      'key_': ['secureStorage', 'appFile', 'memory'],
      'mood_': ['0', '1', '2', '3', '4'],
      '': ['home', 'notes', 'search', 'notebooks', 'voice_notes', 'journal', 'calendar', 'templates', 'tags', 'shared', 'ask_notes', 'settings', 'more'],
    };
    for (final f in families.entries) {
      for (final v in f.value) {
        expect(kStrings.containsKey('${f.key}$v'), isTrue, reason: '${f.key}$v');
      }
    }
  });
}

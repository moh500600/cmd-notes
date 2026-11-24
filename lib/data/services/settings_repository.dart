import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/reminders.dart';

/// Device-level preferences (spec §20). Notes themselves sync; these stay on this device.
class AppSettings {
  final String lang;
  final ThemeMode theme;
  final int accent; // ARGB
  final String font; // tajawal | system
  final double textScale; // whole app
  final double editorFontSize;
  final bool editorToolbarAlways; // false: toolbar collapses while reading
  final int autosaveMs; // editor debounce
  final String recordQuality; // high | normal | low
  final String sttLang; // auto | ar | en
  final bool autoTranscribe;
  final bool autoSync;
  final ReminderPrefs reminders;
  final bool appLock;
  final bool biometric;
  final int lockAfterSec; // lock when the app was in the background this long
  final bool journalLock; // the journal asks for the PIN / biometrics again
  final bool hidePreviews; // notifications without note titles
  final bool aiUseNotes; // Q&A may send excerpts of the user's notes to the assistant
  final String noteSort; // updated | created | title
  final bool gridView;
  final Map<String, String> typeTemplates; // note type → user template id
  const AppSettings({
    this.lang = 'ar',
    this.theme = ThemeMode.system,
    this.accent = 0xFF4F46E5,
    this.font = 'tajawal',
    this.textScale = 1.0,
    this.editorFontSize = 17,
    this.editorToolbarAlways = true,
    this.autosaveMs = 1000,
    this.recordQuality = 'normal',
    this.sttLang = 'auto',
    this.autoTranscribe = false,
    this.autoSync = true,
    this.reminders = const ReminderPrefs(),
    this.appLock = false,
    this.biometric = false,
    this.lockAfterSec = 60,
    this.journalLock = false,
    this.hidePreviews = false,
    this.aiUseNotes = false,
    this.noteSort = 'updated',
    this.gridView = false,
    this.typeTemplates = const {},
  });

  AppSettings copyWith({
    String? lang,
    ThemeMode? theme,
    int? accent,
    String? font,
    double? textScale,
    double? editorFontSize,
    bool? editorToolbarAlways,
    int? autosaveMs,
    String? recordQuality,
    String? sttLang,
    bool? autoTranscribe,
    bool? autoSync,
    ReminderPrefs? reminders,
    bool? appLock,
    bool? biometric,
    int? lockAfterSec,
    bool? journalLock,
    bool? hidePreviews,
    bool? aiUseNotes,
    String? noteSort,
    bool? gridView,
    Map<String, String>? typeTemplates,
  }) => AppSettings(
    lang: lang ?? this.lang,
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    font: font ?? this.font,
    textScale: textScale ?? this.textScale,
    editorFontSize: editorFontSize ?? this.editorFontSize,
    editorToolbarAlways: editorToolbarAlways ?? this.editorToolbarAlways,
    autosaveMs: autosaveMs ?? this.autosaveMs,
    recordQuality: recordQuality ?? this.recordQuality,
    sttLang: sttLang ?? this.sttLang,
    autoTranscribe: autoTranscribe ?? this.autoTranscribe,
    autoSync: autoSync ?? this.autoSync,
    reminders: reminders ?? this.reminders,
    appLock: appLock ?? this.appLock,
    biometric: biometric ?? this.biometric,
    lockAfterSec: lockAfterSec ?? this.lockAfterSec,
    journalLock: journalLock ?? this.journalLock,
    hidePreviews: hidePreviews ?? this.hidePreviews,
    aiUseNotes: aiUseNotes ?? this.aiUseNotes,
    noteSort: noteSort ?? this.noteSort,
    gridView: gridView ?? this.gridView,
    typeTemplates: typeTemplates ?? this.typeTemplates,
  );

  Map<String, dynamic> toJson() => {
    'lang': lang,
    'theme': theme.index,
    'accent': accent,
    'font': font,
    'text_scale': textScale,
    'editor_font': editorFontSize,
    'toolbar_always': editorToolbarAlways,
    'autosave_ms': autosaveMs,
    'record_quality': recordQuality,
    'stt_lang': sttLang,
    'auto_transcribe': autoTranscribe,
    'auto_sync': autoSync,
    'reminders': reminders.toJson(),
    'app_lock': appLock,
    'biometric': biometric,
    'lock_after': lockAfterSec,
    'journal_lock': journalLock,
    'hide_previews': hidePreviews,
    'ai_use_notes': aiUseNotes,
    'note_sort': noteSort,
    'grid': gridView,
    'type_templates': typeTemplates,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T v<T>(String k, T def) => j[k] is T ? j[k] as T : def;
    double dbl(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return AppSettings(
      lang: v('lang', d.lang) == 'en' ? 'en' : 'ar',
      theme: ThemeMode.values[((j['theme'] as num?)?.toInt() ?? 0).clamp(0, 2)],
      accent: (j['accent'] as num?)?.toInt() ?? d.accent,
      font: v('font', d.font),
      textScale: dbl('text_scale', d.textScale).clamp(0.85, 1.4),
      editorFontSize: dbl('editor_font', d.editorFontSize).clamp(12, 30),
      editorToolbarAlways: v('toolbar_always', d.editorToolbarAlways),
      autosaveMs: ((j['autosave_ms'] as num?)?.toInt() ?? d.autosaveMs).clamp(300, 5000),
      recordQuality: v('record_quality', d.recordQuality),
      sttLang: v('stt_lang', d.sttLang),
      autoTranscribe: v('auto_transcribe', d.autoTranscribe),
      autoSync: v('auto_sync', d.autoSync),
      reminders: ReminderPrefs.fromJson(j['reminders'] is Map ? Map<String, dynamic>.from(j['reminders'] as Map) : const {}),
      appLock: v('app_lock', d.appLock),
      biometric: v('biometric', d.biometric),
      lockAfterSec: (j['lock_after'] as num?)?.toInt() ?? d.lockAfterSec,
      journalLock: v('journal_lock', d.journalLock),
      hidePreviews: v('hide_previews', d.hidePreviews),
      aiUseNotes: v('ai_use_notes', d.aiUseNotes),
      noteSort: v('note_sort', d.noteSort),
      gridView: v('grid', d.gridView),
      typeTemplates: j['type_templates'] is Map ? Map<String, String>.from((j['type_templates'] as Map).map((k, v) => MapEntry('$k', '$v'))) : const {},
    );
  }
}

class SettingsRepository {
  final SharedPreferences prefs;
  SettingsRepository(this.prefs);
  static const _key = 'settings_v1';

  AppSettings load() {
    try {
      return AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(prefs.getString(_key) ?? '{}') as Map));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) => prefs.setString(_key, jsonEncode(s.toJson()));
}

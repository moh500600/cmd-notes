import '../entities/entities.dart';
import 'notes_data.dart';

class ReminderPrefs {
  final bool enabled;
  final bool journalDaily;
  final int journalMinute; // minutes after midnight
  final int eventLeadMin; // remind this long before a note's event
  final bool syncAlerts; // notify when sync keeps failing / a backup fails
  const ReminderPrefs({this.enabled = true, this.journalDaily = false, this.journalMinute = 21 * 60, this.eventLeadMin = 30, this.syncAlerts = true});

  ReminderPrefs copyWith({bool? enabled, bool? journalDaily, int? journalMinute, int? eventLeadMin, bool? syncAlerts}) => ReminderPrefs(
    enabled: enabled ?? this.enabled,
    journalDaily: journalDaily ?? this.journalDaily,
    journalMinute: journalMinute ?? this.journalMinute,
    eventLeadMin: eventLeadMin ?? this.eventLeadMin,
    syncAlerts: syncAlerts ?? this.syncAlerts,
  );

  Map<String, dynamic> toJson() => {'enabled': enabled, 'journal': journalDaily, 'journal_min': journalMinute, 'lead': eventLeadMin, 'sync_alerts': syncAlerts};
  factory ReminderPrefs.fromJson(Map<String, dynamic> j) => ReminderPrefs(
    enabled: j['enabled'] as bool? ?? true,
    journalDaily: j['journal'] as bool? ?? false,
    journalMinute: (j['journal_min'] as num?)?.toInt() ?? 21 * 60,
    eventLeadMin: (j['lead'] as num?)?.toInt() ?? 30,
    syncAlerts: j['sync_alerts'] as bool? ?? true,
  );
}

enum ReminderKind { review, remind, event, journal }

class PlannedReminder {
  final int id;
  final DateTime when;
  final ReminderKind kind;
  final String? noteId;
  final String title; // note title (empty for journal)
  final bool daily;
  const PlannedReminder(this.id, this.when, this.kind, this.title, {this.noteId, this.daily = false});
}

/// Stable 31-bit id for an OS notification from a note id + kind.
int alertId(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// Every reminder that should be scheduled now (future only, trashed notes skipped).
List<PlannedReminder> planReminders(NotesData d, ReminderPrefs p, DateTime now, {String untitled = ''}) {
  if (!p.enabled) return const [];
  final out = <PlannedReminder>[];
  for (final n in d.notes) {
    if (n.trashed) continue;
    final title = n.isPrivate ? '' : n.displayTitle(untitled);
    void add(DateTime? t, ReminderKind k) {
      if (t != null && t.isAfter(now)) out.add(PlannedReminder(alertId('${n.id}:${k.name}'), t, k, title, noteId: n.id));
    }

    add(n.reviewAt, ReminderKind.review);
    add(n.remindAt, ReminderKind.remind);
    final ev = n.eventAt;
    if (ev != null) add(ev.subtract(Duration(minutes: p.eventLeadMin)), ReminderKind.event);
  }
  if (p.journalDaily) {
    var t = DateTime(now.year, now.month, now.day, p.journalMinute ~/ 60, p.journalMinute % 60);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    out.add(PlannedReminder(alertId('journal:daily'), t, ReminderKind.journal, '', daily: true));
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  // the OS keeps a limited number of pending alarms (iOS: 64)
  return out.take(60).toList();
}

/// Notes whose reminder is due (for the in-app badge).
List<Note> dueNow(NotesData d, DateTime now) => [
  for (final n in d.notes)
    if (!n.trashed && ((n.remindAt != null && !n.remindAt!.isAfter(now)) || (n.reviewAt != null && !n.reviewAt!.isAfter(now)))) n,
];

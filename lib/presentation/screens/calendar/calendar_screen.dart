import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../editor/note_editor_screen.dart';
import '../journal/journal_screen.dart';
import '../notes/note_actions.dart';

/// Notes by date: events, reminders, reviews, creation day, and journal entries.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focused = DateTime.now(), _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('calendar'))),
      floatingActionButton: FloatingActionButton(
        key: const Key('cal_new'),
        tooltip: l.tr('new_note_on_day'),
        onPressed: () => createAndOpen(context, ref, eventAt: DateTime(_selected.year, _selected.month, _selected.day, 9)),
        child: const Icon(Icons.add_rounded),
      ),
      body: NotesView(
        builder: (context, ref, d) {
          final notes = d.notesOn(_selected);
          final journal = d.journalOn(_selected);
          return PageList(
            children: [
              Card(
                child: TableCalendar<Object>(
                  locale: l.lang,
                  firstDay: DateTime(2000),
                  lastDay: DateTime(2100),
                  focusedDay: _focused,
                  calendarFormat: _format,
                  availableCalendarFormats: {CalendarFormat.month: l.tr('month'), CalendarFormat.twoWeeks: l.tr('two_weeks'), CalendarFormat.week: l.tr('week')},
                  onFormatChanged: (f) => setState(() => _format = f),
                  headerStyle: HeaderStyle(titleTextFormatter: (d, _) => l.month(d)),
                  startingDayOfWeek: l.ar ? StartingDayOfWeek.saturday : StartingDayOfWeek.monday,
                  selectedDayPredicate: (day) => isSameDay(day, _selected),
                  eventLoader: (day) => [...d.notesOn(day).where((n) => n.eventAt != null || n.remindAt != null || n.reviewAt != null), ...d.journalOn(day)],
                  onDaySelected: (s, f) => setState(() { _selected = s; _focused = f; }),
                  onPageChanged: (f) => _focused = f,
                  calendarStyle: CalendarStyle(markerDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle)),
                ),
              ),
              SectionTitle(l.date(_selected)),
              if (notes.isEmpty && journal.isEmpty) NoticeCard(l.tr('nothing_this_day')),
              for (final j in journal)
                InfoTile(
                  icon: Icons.auto_stories_rounded,
                  color: AppColors.amber,
                  title: '${l.tr('journal')}${j.mood == null ? '' : ' · ${l.tr('mood_${j.mood!.clamp(0, 4)}')}'}',
                  subtitle: j.title,
                  onTap: () => openJournalEntry(context, ref, j.date),
                ),
              for (final n in notes) _tile(context, l, n),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, L10n l, Note n) {
    bool same(DateTime? t) => t != null && isSameDay(t, _selected);
    final why = [
      if (same(n.eventAt)) '${l.tr('event_date')} ${l.time(n.eventAt!)}',
      if (same(n.remindAt)) '${l.tr('reminder')} ${l.time(n.remindAt!)}',
      if (same(n.reviewAt)) l.tr('review_date'),
      if (same(n.createdAt)) l.tr('created'),
    ].join(' · ');
    return InfoTile(
      icon: typeIcon(n.type),
      color: AppColors.type(n.type),
      title: n.displayTitle(l.tr('untitled')),
      subtitle: why,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id))),
    );
  }
}

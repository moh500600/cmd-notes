import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/autosave_bus.dart';
import '../../../core/utils/text_tools.dart';
import '../../../data/services/file_service.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/delta_doc.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../editor/embeds.dart';
import '../lock/lock_screen.dart';

const kMoodIcons = [
  Icons.sentiment_very_dissatisfied_rounded,
  Icons.sentiment_dissatisfied_rounded,
  Icons.sentiment_neutral_rounded,
  Icons.sentiment_satisfied_rounded,
  Icons.sentiment_very_satisfied_rounded,
];
const kMoodColors = [Color(0xFFE11D48), Color(0xFFF97316), Color(0xFFA3A3A3), Color(0xFF84CC16), Color(0xFF16A34A)];

Widget moodIcon(int? m, {double size = 20}) => m == null ? const SizedBox() : Icon(kMoodIcons[m.clamp(0, 4)], color: kMoodColors[m.clamp(0, 4)], size: size);

/// The journal unlock lasts until the app locks or goes to the background.
class JournalUnlock extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(lockProvider);
    return false;
  }

  void set(bool v) => state = v;
}

final journalUnlockedProvider = NotifierProvider<JournalUnlock, bool>(JournalUnlock.new);

Future<bool> _unlockJournal(BuildContext context, WidgetRef ref) async {
  final s = ref.read(settingsProvider);
  if (!s.journalLock || ref.read(journalUnlockedProvider)) return true;
  final ok = await verifyIdentity(context, ref);
  if (ok) ref.read(journalUnlockedProvider.notifier).set(true);
  return ok;
}

Future<void> openJournalEntry(BuildContext context, WidgetRef ref, DateTime day) async {
  if (!await _unlockJournal(context, ref)) return;
  if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => JournalEntryScreen(day: day)));
}

/// Daily journal: calendar of entries with their mood, and today's page.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});
  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    final unlocked = ref.watch(journalUnlockedProvider);
    if (s.journalLock && !unlocked) {
      return Scaffold(
        appBar: AppBar(title: Text(l.tr('journal'))),
        body: EmptyState(
          icon: Icons.lock_rounded,
          title: l.tr('journal_locked'),
          subtitle: l.tr('journal_locked_sub'),
          action: FilledButton.icon(onPressed: () => _unlockJournal(context, ref), icon: const Icon(Icons.lock_open_rounded), label: Text(l.tr('unlock'))),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('journal'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('journal_today'),
        onPressed: () => openJournalEntry(context, ref, DateTime.now()),
        icon: const Icon(Icons.edit_rounded),
        label: Text(l.tr('write_today')),
      ),
      body: NotesView(
        builder: (context, ref, d) {
          final byDay = <String, JournalEntry>{for (final j in d.journal) dateKeyOf(j.date): j};
          final sel = byDay[dateKeyOf(_selected)];
          final recent = [...d.journal]..sort((a, b) => b.date.compareTo(a.date));
          final moods = d.journal.where((j) => j.mood != null && j.date.isAfter(DateTime.now().subtract(const Duration(days: 30)))).map((j) => j.mood!).toList();
          return PageList(
            children: [
              Card(
                child: TableCalendar<JournalEntry>(
                  locale: l.lang,
                  firstDay: DateTime(2000),
                  lastDay: DateTime(2100),
                  focusedDay: _focused,
                  startingDayOfWeek: l.ar ? StartingDayOfWeek.saturday : StartingDayOfWeek.monday,
                  availableCalendarFormats: const {CalendarFormat.month: ''},
                  headerStyle: HeaderStyle(titleCentered: true, formatButtonVisible: false, titleTextFormatter: (d, _) => l.month(d)),
                  selectedDayPredicate: (day) => isSameDay(day, _selected),
                  eventLoader: (day) => [?byDay[dateKeyOf(day)]],
                  onDaySelected: (s, f) => setState(() { _selected = s; _focused = f; }),
                  onPageChanged: (f) => _focused = f,
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) => events.isEmpty
                        ? null
                        : Positioned(bottom: 1, child: events.first.mood == null ? const Text('•') : moodIcon(events.first.mood, size: 13)),
                  ),
                ),
              ),
              if (moods.isNotEmpty)
                NoticeCard(l.tr('mood_avg', {'m': l.tr('mood_${(moods.reduce((a, b) => a + b) / moods.length).round().clamp(0, 4)}'), 'n': '${moods.length}'}), icon: Icons.insights_rounded, color: AppColors.amber),
              SectionTitle(l.date(_selected)),
              if (sel == null)
                OutlinedButton.icon(onPressed: () => openJournalEntry(context, ref, _selected), icon: const Icon(Icons.add_rounded), label: Text(l.tr('write_this_day')))
              else
                _entryCard(context, l, sel),
              if (recent.isNotEmpty) ...[
                SectionTitle(l.tr('recent_entries')),
                for (final j in recent.take(10)) _entryCard(context, l, j),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _entryCard(BuildContext context, L10n l, JournalEntry j) => InfoTile(
    icon: j.mood == null ? Icons.auto_stories_rounded : kMoodIcons[j.mood!.clamp(0, 4)],
    color: j.mood == null ? AppColors.amber : kMoodColors[j.mood!.clamp(0, 4)],
    title: j.title.isEmpty ? l.date(j.date) : j.title,
    subtitle: '${l.date(j.date)} · ${preview(j.plainText, 90)}',
    onTap: () => openJournalEntry(context, ref, j.date),
  );
}

String dateKeyOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One day's journal page (autosaves).
class JournalEntryScreen extends ConsumerStatefulWidget {
  final DateTime day;
  const JournalEntryScreen({super.key, required this.day});
  @override
  ConsumerState<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends ConsumerState<JournalEntryScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _ach = TextEditingController();
  final _thoughts = TextEditingController();
  final _goals = TextEditingController();
  String? _id;
  int? _mood;
  Timer? _t;
  bool _dirty = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    AutosaveBus.register(this, _save);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final d = await ref.read(notesProvider.future);
      final j = d.journalOn(widget.day).firstOrNull;
      if (j != null) {
        _id = j.id;
        _title.text = j.title;
        _body.text = j.plainText;
        _ach.text = j.achievements;
        _thoughts.text = j.thoughts;
        _goals.text = j.goals;
        _mood = j.mood;
      }
      for (final c in [_title, _body, _ach, _thoughts, _goals]) {
        c.addListener(_changed);
      }
      if (mounted) setState(() => _loaded = true);
    });
  }

  void _changed() {
    _dirty = true;
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 900), _save);
  }

  Future<void> _save() async {
    if (!_dirty) return;
    _dirty = false;
    final repo = ref.read(repoProvider);
    if (repo == null) return;
    _id = await repo.saveJournal(
      id: _id,
      date: widget.day,
      title: _title.text.trim(),
      content: DeltaDoc.fromPlain(_body.text).toJson(),
      mood: _mood,
      achievements: _ach.text,
      thoughts: _thoughts.text,
      goals: _goals.text,
    );
  }

  @override
  void dispose() {
    _t?.cancel();
    AutosaveBus.unregister(this);
    _save();
    for (final c in [_title, _body, _ach, _thoughts, _goals]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final files = ref.read(fileServiceProvider);
    if (files == null) return;
    _dirty = true;
    await _save();
    if (!mounted || _id == null) return;
    await guard(context, () async {
      final f = await files.pick(PickKind.image);
      if (f != null) await files.addPicked(f, ownerKind: 'journal', ownerId: _id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    Widget field(TextEditingController c, String label, IconData icon, {int lines = 3, Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key,
        controller: c,
        minLines: lines,
        maxLines: null,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), alignLabelWithHint: true),
      ),
    );
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.date(widget.day)),
          actions: [
            IconButton(tooltip: l.tr('add_photo'), onPressed: _addPhoto, icon: const Icon(Icons.add_photo_alternate_rounded)),
            if (_id != null)
              IconButton(
                tooltip: l.tr('delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (!await confirm(context, l.tr('delete_entry_confirm'))) return;
                  _dirty = false;
                  await ref.read(repoProvider)!.delete('journal_entries', _id!);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
        body: PageList(
          children: [
            Text(l.tr('how_was_day'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < kMoodIcons.length; i++)
                  GestureDetector(
                    key: Key('mood_$i'),
                    onTap: () {
                      setState(() => _mood = _mood == i ? null : i);
                      _changed();
                    },
                    child: AnimatedScale(
                      scale: _mood == i ? 1.35 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Opacity(
                        opacity: _mood == null || _mood == i ? 1 : 0.4,
                        child: Tooltip(message: l.tr('mood_$i'), child: moodIcon(i, size: 40)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            field(_title, l.tr('title'), Icons.title_rounded, lines: 1, key: const Key('journal_title')),
            field(_body, l.tr('journal_body'), Icons.edit_note_rounded, lines: 6, key: const Key('journal_body')),
            field(_ach, l.tr('achievements'), Icons.emoji_events_rounded),
            field(_thoughts, l.tr('thoughts'), Icons.psychology_rounded),
            field(_goals, l.tr('goals'), Icons.flag_rounded),
            if (_id != null) _photos(l),
            NoticeCard(l.tr('journal_encrypted'), icon: Icons.enhanced_encryption_rounded, color: AppColors.success),
          ],
        ),
      ),
    );
  }

  Widget _photos(L10n l) => Consumer(
    builder: (context, ref, _) {
      final d = ref.watch(notesProvider).value;
      final atts = d?.attachments.where((a) => a.ownerKind == 'journal' && a.ownerId == _id).toList() ?? [];
      if (atts.isEmpty) return const SizedBox();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in atts)
              GestureDetector(
                onLongPress: () async {
                  if (await confirm(context, l.tr('delete_file_confirm'))) await ref.read(fileServiceProvider)?.remove(a);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 110,
                    height: 110,
                    child: ref.watch(attachmentBytesProvider(a.id)).maybeWhen(data: (b) => b == null ? const Icon(Icons.image_rounded) : Image.memory(b, fit: BoxFit.cover), orElse: () => const Center(child: CircularProgressIndicator())),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

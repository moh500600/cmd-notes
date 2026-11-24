import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/text_tools.dart';
import '../../../data/db/search_index.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/notes_data.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../editor/note_editor_screen.dart';
import '../journal/journal_screen.dart';
import '../voice/voice_screen.dart';

/// Instant search (Arabic-aware) across notes, folders, tags, file names, text in images,
/// voice transcripts and the journal — with filters by type, notebook and date.
class SearchScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const SearchScreen({super.key, this.embedded = false});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = [];
  String _type = '', _notebook = '', _range = 'all', _kind = 'all';
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final repo = ref.read(repoProvider);
      if (repo == null) return;
      setState(() => _searching = true);
      final hits = v.trim().isEmpty ? <SearchHit>[] : await repo.search(v);
      if (mounted && v == _q.text) setState(() { _hits = hits; _searching = false; });
    });
  }

  bool _inRange(DateTime t) {
    final now = DateTime.now();
    final start = switch (_range) {
      'today' => DateTime(now.year, now.month, now.day),
      'week' => now.subtract(const Duration(days: 7)),
      'month' => now.subtract(const Duration(days: 31)),
      'year' => now.subtract(const Duration(days: 365)),
      _ => null,
    };
    return start == null || t.isAfter(start);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: TextField(
          key: const Key('search_field'),
          controller: _q,
          autofocus: !widget.embedded,
          onChanged: _changed,
          decoration: InputDecoration(
            hintText: l.tr('search_hint'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _q.clear();
                      _changed('');
                    },
                  ),
            isDense: true,
          ),
        ),
      ),
      body: NotesView(
        builder: (context, ref, d) {
          final q = _q.text.trim();
          final notes = <Note>[];
          final voices = <VoiceRecording>[];
          for (final h in _hits) {
            if (h.kind == 'note') {
              final n = d.noteById[h.id];
              if (n == null || n.trashed) continue;
              if (_type.isNotEmpty && n.type != _type) continue;
              if (_notebook.isNotEmpty && !(n.notebookId != null && d.tree.descendantsOf(_notebook).contains(n.notebookId))) continue;
              if (!_inRange(n.updatedAt)) continue;
              notes.add(n);
            } else if (h.kind == 'voice') {
              final v = d.voices.where((x) => x.id == h.id).firstOrNull;
              if (v != null && _inRange(v.createdAt) && (_notebook.isEmpty || v.notebookId == _notebook)) voices.add(v);
            }
          }
          final nq = normalizeForSearch(q);
          final journal = q.isEmpty || _type.isNotEmpty || _notebook.isNotEmpty
              ? <JournalEntry>[]
              : d.journal.where((j) => _inRange(j.date) && searchTokens(q).every((w) => normalizeForSearch('${j.title} ${j.plainText} ${j.achievements} ${j.thoughts} ${j.goals}').contains(w))).toList();
          final showNotes = _kind == 'all' || _kind == 'notes';
          final showVoice = _kind == 'all' || _kind == 'voice';
          final showJournal = _kind == 'all' || _kind == 'journal';
          final total = (showNotes ? notes.length : 0) + (showVoice ? voices.length : 0) + (showJournal ? journal.length : 0);
          return Column(
            children: [
              _filters(l, d),
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: q.isEmpty
                    ? EmptyState(icon: Icons.manage_search_rounded, title: l.tr('search_start'), subtitle: l.tr('search_start_sub'))
                    : total == 0
                    ? EmptyState(icon: Icons.search_off_rounded, title: l.tr('no_results'), subtitle: nq.isEmpty ? null : l.tr('no_results_sub'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                        children: [
                          Padding(padding: const EdgeInsets.all(4), child: Text(l.tr('n_results', {'n': '$total'}), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                          if (showNotes)
                            for (final n in notes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: NoteCard(note: n, data: d, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: n.id)))),
                              ),
                          if (showVoice)
                            for (final v in voices)
                              InfoTile(
                                icon: Icons.graphic_eq_rounded,
                                color: AppColors.type('voice'),
                                title: v.title,
                                subtitle: preview(v.transcript, 100),
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoiceDetailScreen(voiceId: v.id))),
                              ),
                          if (showJournal)
                            for (final j in journal)
                              InfoTile(
                                icon: Icons.auto_stories_rounded,
                                color: AppColors.amber,
                                title: j.title.isEmpty ? l.date(j.date) : j.title,
                                subtitle: preview(j.plainText, 100),
                                onTap: () => openJournalEntry(context, ref, j.date),
                              ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filters(L10n l, NotesData d) {
    Widget menu<T>(String label, IconData icon, String value, List<(String, String)> opts, ValueChanged<String> set) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: PopupMenuButton<String>(
        onSelected: set,
        itemBuilder: (_) => [for (final (k, t) in opts) CheckedPopupMenuItem(value: k, checked: k == value, child: Text(t))],
        child: Chip(
          avatar: Icon(icon, size: 18),
          label: Text(value.isEmpty || value == 'all' ? label : opts.firstWhere((o) => o.$1 == value, orElse: () => (value, label)).$2),
          backgroundColor: value.isEmpty || value == 'all' ? null : Theme.of(context).colorScheme.primaryContainer,
        ),
      ),
    );
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          menu(l.tr('everything'), Icons.layers_rounded, _kind, [('all', l.tr('everything')), ('notes', l.tr('notes')), ('voice', l.tr('voice_notes')), ('journal', l.tr('journal'))], (v) => setState(() => _kind = v)),
          menu(l.tr('note_type'), Icons.category_rounded, _type, [('', l.tr('all_types')), for (final t in kNoteTypes) (t, typeLabel(l, t))], (v) => setState(() => _type = v)),
          menu(l.tr('notebook'), Icons.menu_book_rounded, _notebook, [('', l.tr('all_notebooks')), for (final (nb, depth) in d.tree.flat()) (nb.id, '${'  ' * depth}${nb.name}')], (v) => setState(() => _notebook = v)),
          menu(l.tr('date'), Icons.date_range_rounded, _range, [('all', l.tr('any_time')), ('today', l.tr('today')), ('week', l.tr('this_week')), ('month', l.tr('this_month')), ('year', l.tr('this_year'))], (v) => setState(() => _range = v)),
        ],
      ),
    );
  }
}

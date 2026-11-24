import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/text_tools.dart';
import '../../../data/services/file_service.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/delta_doc.dart';
import '../../../domain/services/note_format.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../editor/note_editor_screen.dart';

String formatDuration(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(r)}' : '${two(m)}:${two(r)}';
}

/// All recordings: record, play, search transcripts.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});
  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('voice_notes'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('record_fab'),
        onPressed: () => showRecorderSheet(context, ref),
        icon: const Icon(Icons.mic_rounded),
        label: Text(l.tr('record')),
      ),
      body: NotesView(
        builder: (context, ref, d) {
          final q = normalizeForSearch(_q.trim());
          final list = d.voices.where((v) => q.isEmpty || normalizeForSearch('${v.title} ${v.description} ${v.transcript}').contains(q)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: l.tr('search_recordings'), isDense: true),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(icon: Icons.mic_none_rounded, title: l.tr('no_recordings'), subtitle: l.tr('no_recordings_sub'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final v = list[i];
                          final nb = v.notebookId == null ? null : d.tree.byId[v.notebookId];
                          return InfoTile(
                            icon: Icons.graphic_eq_rounded,
                            color: AppColors.type('voice'),
                            title: v.title.isEmpty ? l.tr('voice_note') : v.title,
                            subtitle: [
                              formatDuration(v.durationMs),
                              l.dateTime(v.createdAt),
                              ?nb?.name,
                              if (v.transcript.isNotEmpty) '📝 ${preview(v.transcript, 60)}',
                            ].join(' · '),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VoiceDetailScreen(voiceId: v.id))),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Records with pause / resume. Returns the saved recording's id.
Future<String?> showRecorderSheet(BuildContext context, WidgetRef ref, {String? noteId, String? notebookId}) =>
    showModalBottomSheet<String>(context: context, isDismissible: false, enableDrag: false, builder: (_) => _Recorder(noteId: noteId, notebookId: notebookId));

class _Recorder extends ConsumerStatefulWidget {
  final String? noteId, notebookId;
  const _Recorder({this.noteId, this.notebookId});
  @override
  ConsumerState<_Recorder> createState() => _RecorderState();
}

class _RecorderState extends ConsumerState<_Recorder> {
  final _rec = AudioRecorder();
  Timer? _tick;
  final _sw = Stopwatch();
  bool _started = false, _paused = false, _saving = false;
  String? _error;
  String? _path;
  double _level = 0;
  StreamSubscription<Amplitude>? _amp;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) return setState(() => _error = 'mic_denied');
      final q = ref.read(settingsProvider).recordQuality;
      var enc = AudioEncoder.aacLc;
      var ext = '.m4a';
      if (!await _rec.isEncoderSupported(enc)) {
        enc = AudioEncoder.wav;
        ext = '.wav';
      }
      final dir = await FileService.tempDir();
      _path = p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}$ext');
      await _rec.start(
        RecordConfig(encoder: enc, bitRate: q == 'high' ? 192000 : (q == 'low' ? 48000 : 96000), sampleRate: q == 'low' ? 22050 : 44100, numChannels: 1),
        path: _path!,
      );
      _sw.start();
      _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 150)).listen((a) {
        if (mounted) setState(() => _level = ((a.current + 50) / 50).clamp(0, 1).toDouble());
      });
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _started = true);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _rec.resume();
      _sw.start();
    } else {
      await _rec.pause();
      _sw.stop();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _stop({required bool save}) async {
    _tick?.cancel();
    _sw.stop();
    _amp?.cancel();
    setState(() => _saving = true);
    final path = await _rec.stop() ?? _path;
    if (!save || path == null) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context);
      return;
    }
    final files = ref.read(fileServiceProvider);
    if (files == null || !mounted) return;
    final l = context.l;
    final title = '${l.tr('recording')} ${l.dateTime(DateTime.now())}';
    try {
      final id = await files.addVoice(File(path), title: title, durationMs: _sw.elapsedMilliseconds, noteId: widget.noteId, notebookId: widget.notebookId);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        toast(context, errorText(context, e));
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _amp?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.tr(_paused ? 'recording_paused' : 'recording_now'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 18),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 90 + 50 * (_paused ? 0 : _level),
              height: 90 + 50 * (_paused ? 0 : _level),
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.danger.withValues(alpha: _paused ? 0.15 : 0.25)),
              child: Icon(_paused ? Icons.pause_rounded : Icons.mic_rounded, size: 44, color: AppColors.danger),
            ),
            const SizedBox(height: 14),
            Text(formatDuration(_sw.elapsedMilliseconds), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.tr(_error!), style: TextStyle(color: cs.error), textAlign: TextAlign.center)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(onPressed: _saving ? null : () => _stop(save: false), icon: const Icon(Icons.close_rounded), label: Text(l.tr('cancel'))),
                IconButton.filledTonal(
                  key: const Key('rec_pause'),
                  iconSize: 32,
                  onPressed: _started && !_saving ? _togglePause : null,
                  icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  tooltip: l.tr(_paused ? 'resume' : 'pause'),
                ),
                FilledButton.icon(
                  key: const Key('rec_save'),
                  onPressed: _started && !_saving ? () => _stop(save: true) : null,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(l.tr('save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceDetailScreen extends ConsumerStatefulWidget {
  final String voiceId;
  const VoiceDetailScreen({super.key, required this.voiceId});
  @override
  ConsumerState<VoiceDetailScreen> createState() => _VoiceDetailScreenState();
}

class _VoiceDetailScreenState extends ConsumerState<VoiceDetailScreen> {
  final _player = AudioPlayer();
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false, _busy = false, _loaded = false;
  double _speed = 1.0;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPositionChanged.listen((d) => setState(() => _pos = d)));
    _subs.add(_player.onDurationChanged.listen((d) => setState(() => _dur = d)));
    _subs.add(_player.onPlayerComplete.listen((_) => setState(() {
      _playing = false;
      _pos = Duration.zero;
    })));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle(VoiceRecording v) async {
    if (_playing) {
      await _player.pause();
      return setState(() => _playing = false);
    }
    await guard(context, () async {
      if (!_loaded) {
        final f = await ref.read(fileServiceProvider)!.voiceFile(v);
        await _player.setSource(DeviceFileSource(f.path));
        _loaded = true;
      }
      await _player.setPlaybackRate(_speed);
      await _player.resume();
      setState(() => _playing = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return NotesView(
      builder: (context, ref, d) {
        final v = d.voices.where((x) => x.id == widget.voiceId).firstOrNull;
        if (v == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(l.tr('err_not_found'))));
        final repo = ref.read(repoProvider)!;
        final total = _dur.inMilliseconds > 0 ? _dur : Duration(milliseconds: v.durationMs);
        final nb = v.notebookId == null ? null : d.tree.byId[v.notebookId];
        final linked = v.noteId == null ? null : d.noteById[v.noteId];
        return Scaffold(
          appBar: AppBar(
            title: Text(v.title.isEmpty ? l.tr('voice_note') : v.title),
            actions: [
              IconButton(
                tooltip: l.tr('delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (!await confirm(context, l.tr('delete_recording_confirm'))) return;
                  if (!context.mounted) return;
                  if (await guard(context, () => ref.read(fileServiceProvider)!.removeVoice(v)) && context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          body: PageList(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Slider(
                        value: _pos.inMilliseconds.clamp(0, total.inMilliseconds > 0 ? total.inMilliseconds : 1).toDouble(),
                        max: (total.inMilliseconds > 0 ? total.inMilliseconds : 1).toDouble(),
                        onChanged: (x) => _player.seek(Duration(milliseconds: x.round())),
                      ),
                      Row(
                        children: [
                          Text(formatDuration(_pos.inMilliseconds)),
                          const Spacer(),
                          Text(formatDuration(total.inMilliseconds)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(onPressed: () => _player.seek(_pos - const Duration(seconds: 10)), icon: const Icon(Icons.replay_10_rounded)),
                          const SizedBox(width: 8),
                          IconButton.filled(key: const Key('play'), iconSize: 40, onPressed: () => _toggle(v), icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                          const SizedBox(width: 8),
                          IconButton(onPressed: () => _player.seek(_pos + const Duration(seconds: 10)), icon: const Icon(Icons.forward_10_rounded)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<double>(
                        segments: [for (final s in [0.5, 1.0, 1.25, 1.5, 2.0]) ButtonSegment(value: s, label: Text('${s}x'))],
                        selected: {_speed},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) async {
                          setState(() => _speed = s.first);
                          if (_playing) await _player.setPlaybackRate(_speed);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InfoTile(
                icon: Icons.edit_rounded,
                color: AppColors.primary,
                title: l.tr('rename'),
                subtitle: v.title,
                onTap: () async {
                  final t = await promptText(context, l.tr('rename'), initial: v.title);
                  if (t != null && t.trim().isNotEmpty) await repo.saveVoice(v.id, {'title': t.trim()});
                },
              ),
              InfoTile(
                icon: Icons.notes_rounded,
                color: AppColors.info,
                title: l.tr('description'),
                subtitle: v.description.isEmpty ? l.tr('not_set') : v.description,
                onTap: () async {
                  final t = await promptText(context, l.tr('description'), initial: v.description, maxLines: 4);
                  if (t != null) await repo.saveVoice(v.id, {'description': t.trim()});
                },
              ),
              InfoTile(
                icon: Icons.folder_rounded,
                color: AppColors.amber,
                title: l.tr('notebook'),
                subtitle: nb?.name ?? l.tr('no_notebook'),
                onTap: () async {
                  final to = await pickNotebook(context, d, current: v.notebookId);
                  if (to != null) await repo.saveVoice(v.id, {'notebook_id': to.isEmpty ? null : to});
                },
              ),
              if (linked != null)
                InfoTile(
                  icon: Icons.link_rounded,
                  color: AppColors.teal,
                  title: l.tr('linked_note'),
                  subtitle: linked.displayTitle(l.tr('untitled')),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: linked.id))),
                ),
              SectionTitle(l.tr('transcript')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (v.transcript.isEmpty)
                        Text(l.tr('no_transcript'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                      else
                        SelectableText(v.transcript, style: const TextStyle(height: 1.6)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                              onPressed: () async {
                                final t = await promptText(context, l.tr('edit_transcript'), initial: v.transcript, maxLines: 10);
                                if (t != null) await repo.saveVoice(v.id, {'transcript': t});
                              },
                              icon: const Icon(Icons.edit_note_rounded),
                              label: Text(l.tr('edit')),
                            ),
                          if (v.transcript.isNotEmpty)
                            OutlinedButton.icon(
                              key: const Key('voice_to_note'),
                              onPressed: () => _toNote(v),
                              icon: const Icon(Icons.auto_awesome_rounded),
                              label: Text(l.tr('voice_to_note')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Transcript (typed by you) → a note.
  Future<void> _toNote(VoiceRecording v) async {
    final repo = ref.read(repoProvider)!;
    final l = context.l;
    setState(() => _busy = true);
    final title = v.title;
    final doc = DeltaDoc.fromPlain(v.transcript);
    final id = await repo.createNote(type: 'voice', title: title, content: doc.toJson(), notebookId: v.notebookId);
    await repo.saveVoice(v.id, {'note_id': id});
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
  }
}

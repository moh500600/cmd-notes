import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/platform/desktop_files.dart';
import '../../../core/platform/platform_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/autosave_bus.dart';
import '../../../core/utils/text_tools.dart';
import '../../../core/utils/time.dart';
import '../../../data/repositories/notes_repository.dart';
import '../../../data/services/export_service.dart';
import '../../../data/services/file_service.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/delta_doc.dart';
import '../../../domain/services/note_format.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/note_widgets.dart';
import '../sharing/share_sheet.dart';
import '../voice/voice_screen.dart';
import 'embeds.dart';
import 'vault_dialogs.dart';

/// The note editor: rich text (Arabic RTL and English), autosave with a crash-safe draft,
/// undo/redo, counters, attachments, AI tools and every per-note action.
class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;
  const NoteEditorScreen({super.key, required this.noteId});
  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  QuillController? _c;
  final _title = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final NotesRepository _repo;
  StreamSubscription<DocChange>? _sub;
  Timer? _draftTimer, _saveTimer;
  Note? _note;
  bool _locked = false;
  bool _dirty = false;
  bool _saving = false;
  DateTime? _savedAt;
  String? _error;
  int _words = 0, _chars = 0;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(repoProvider)!;
    AutosaveBus.register(this, _save);
    _load();
  }

  Future<void> _load() async {
    final n = await _repo.note(widget.noteId);
    if (!mounted) return;
    if (n == null) return setState(() => _error = 'err_not_found');
    _note = n;
    if (n.isPrivate && _repo.vault == null) return setState(() => _locked = true);
    try {
      final o = _repo.open(n);
      // A draft newer than the note (the app was closed mid-edit) wins.
      final draft = (await _repo.store.db.query('drafts', where: 'note_id = ?', whereArgs: [n.id])).firstOrNull;
      var content = o.content, title = n.title;
      if (draft != null && (draft['saved_at'] as String).compareTo(n.r['updated_at'] as String? ?? '') > 0) {
        content = draft['content'] as String;
        title = draft['title'] as String;
        _dirty = true;
      }
      _setup(title, content);
    } on AppException catch (e) {
      setState(() => _error = e.key);
    }
  }

  void _setup(String title, String content) {
    Document doc;
    try {
      final ops = DeltaDoc.parse(content).ops;
      doc = Document.fromJson(ops.isEmpty ? [{'insert': '\n'}] : ops);
    } catch (_) {
      doc = Document()..insert(0, DeltaDoc.parse(content).plainText);
    }
    _title.text = title;
    final c = QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0));
    _sub = c.document.changes.listen((_) => _changed());
    _title.addListener(_changed);
    c.addListener(() {
      if (mounted) setState(() {}); // undo/redo buttons
    });
    setState(() {
      _c = c;
      _locked = false;
      _count();
    });
    if (_dirty) _save();
  }

  void _count() {
    final c = _c;
    if (c == null) return;
    final plain = c.document.toPlainText().replaceAll(Embed.kObjectReplacementCharacter, '');
    _words = wordCount('${_title.text} $plain');
    _chars = charCount(plain.trimRight());
  }

  void _changed() {
    _dirty = true;
    _count();
    final ms = ref.read(settingsProvider).autosaveMs;
    // 1) the crash-safe draft almost immediately, 2) the note itself after a short pause.
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), () {
      final c = _c;
      if (c != null) _repo.writeDraft(widget.noteId, _title.text, jsonEncode(c.document.toDelta().toJson()));
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(Duration(milliseconds: ms), _save);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final c = _c;
    if (c == null || !_dirty || _saving) return;
    _saving = true;
    _dirty = false;
    try {
      await _repo.saveContent(widget.noteId, _title.text, jsonEncode(c.document.toDelta().toJson()));
      _savedAt = DateTime.now();
    } catch (e) {
      _dirty = true;
      if (mounted) toast(context, errorText(context, e));
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _saveTimer?.cancel();
    AutosaveBus.unregister(this);
    _save(); // the store outlives the screen
    _sub?.cancel();
    _c?.dispose();
    _title.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<Note?> _fresh() async => _note = await _repo.note(widget.noteId);

  // ------------------------------------------------------------------ inserts
  Future<void> _insertImage({bool camera = false}) async {
    final files = ref.read(fileServiceProvider);
    if (files == null) return;
    await guard(context, () async {
      String name;
      Uint8List bytes;
      if (camera || PlatformSupport.isMobile) {
        final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, imageQuality: 85, maxWidth: 2400);
        if (x == null) return;
        name = x.name;
        bytes = await x.readAsBytes();
      } else {
        final f = await files.pick(PickKind.image);
        if (f == null) return;
        name = f.name;
        bytes = await f.readAsBytes();
      }
      final id = await files.addBytes(name, bytes, noteId: widget.noteId);
      insertEmbed(_c!, Embeds.image, {'id': id, 'name': name});
    });
  }

  Future<void> _attachFile(PickKind kind) async {
    final files = ref.read(fileServiceProvider);
    if (files == null) return;
    await guard(context, () async {
      final f = await files.pick(kind);
      if (f == null) return;
      final id = await files.addPicked(f, noteId: widget.noteId);
      if (fileTypeOf(f.name) == 'image') {
        insertEmbed(_c!, Embeds.image, {'id': id, 'name': f.name});
      } else {
        insertEmbed(_c!, Embeds.file, {'id': id, 'name': f.name});
      }
    });
  }

  Future<void> _insertTable() async {
    final rows = await editTable(context, [
      ['', '', ''],
      ['', '', ''],
    ]);
    if (rows == null || rows.isEmpty) return;
    insertEmbed(_c!, Embeds.table, {'rows': rows});
  }

  Future<void> _record() async {
    final id = await showRecorderSheet(context, ref, noteId: widget.noteId, notebookId: _note?.notebookId);
    if (id != null && mounted) toast(context, context.tr('voice_saved'));
  }

  /// Inserts AI / imported Markdown at the cursor as formatted text.
  void insertMarkdown(String md) {
    final c = _c!;
    final (_, doc) = NoteFormat.fromMarkdown(md, takeTitle: false);
    final idx = c.selection.isValid ? c.selection.start : c.document.length - 1;
    final ops = doc.ops;
    final change = Delta()..retain(idx);
    for (final o in ops) {
      change.push(Operation.fromJson(o));
    }
    c.compose(change, TextSelection.collapsed(offset: idx), ChangeSource.local);
  }

  void replaceSelectionOrAll(String text) {
    final c = _c!;
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed) {
      c.replaceText(sel.start, sel.end - sel.start, text, TextSelection.collapsed(offset: sel.start + text.length));
    } else {
      c.replaceText(0, c.document.length - 1, text, TextSelection.collapsed(offset: text.length));
    }
  }

  String _selectedOrAll() {
    final c = _c!;
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed) return c.document.getPlainText(sel.start, sel.end - sel.start);
    return '${_title.text}\n${c.document.toPlainText()}'.trim();
  }

  // ------------------------------------------------------------------ menu actions
  Future<void> _menu(String v) async {
    final n = await _fresh();
    if (n == null || !mounted) return;
    final l = context.l;
    switch (v) {
      case 'pin':
        await _repo.setPinned(n.id, !n.pinned);
      case 'fav':
        await _repo.setFavorite(n.id, !n.favorite);
      case 'tags':
        await editNoteTags(context, ref, n.id);
      case 'move':
        final d = await ref.read(notesProvider.future);
        if (!mounted) return;
        final to = await pickNotebook(context, d, current: n.notebookId);
        if (to != null) await _repo.move(n.id, to.isEmpty ? null : to);
      case 'type':
        final t = await _pickType(n.type);
        if (t != null) await _repo.update(n.id, {'note_type': t});
      case 'color':
        final c = await _pickColor(n.color);
        if (c != null) await _repo.update(n.id, {'color': c});
      case 'dates':
        await editNoteDates(context, ref, n);
      case 'private':
        await _togglePrivate(n);
      case 'files':
        await showNoteFiles(context, ref, n.id, onInsert: (a) {
          insertEmbed(_c!, a.isImage ? Embeds.image : Embeds.file, {'id': a.id, 'name': a.title});
        });
      case 'share':
        await _save();
        if (!mounted) return;
        if (n.isPrivate) return toast(context, l.tr('private_cannot_share'));
        await showShareSheet(context, ref, noteId: n.id, title: n.displayTitle(l.tr('untitled')));
      case 'template':
        await _save();
        if (!mounted) return;
        final name = await promptText(context, l.tr('save_as_template'), initial: n.title);
        if (name == null || name.trim().isEmpty) return;
        await _repo.saveTemplate(name: name, type: n.type, content: jsonEncode(_c!.document.toDelta().toJson()));
        if (mounted) toast(context, l.tr('template_saved'));
      case 'duplicate':
        await _save();
        final id = await _repo.duplicate(n.id, suffix: ' (${l.tr('copy')})');
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
      case 'info':
        _info(n);
      case 'archive':
        await _save();
        await _repo.archive(n.id, !n.archived);
        if (mounted) toast(context, l.tr(n.archived ? 'unarchived' : 'archived_done'));
      case 'trash':
        await _save();
        await _repo.trash(n.id);
        if (mounted) {
          toast(context, l.tr('moved_to_trash'));
          Navigator.pop(context);
        }
      default:
        if (v.startsWith('export_')) await _export(ExportFormat.values.byName(v.substring(7)));
    }
    await _fresh();
    if (mounted) setState(() {});
  }

  Future<void> _togglePrivate(Note n) async {
    final l = context.l;
    await _save();
    if (!mounted) return;
    if (!await ensureVaultUnlocked(context, ref)) return;
    if (!n.isPrivate) {
      if (!mounted || !await confirm(context, l.tr('make_private_confirm'), okLabel: l.tr('encrypt'), danger: false)) return;
    }
    if (!mounted) return;
    await guard(context, () => _repo.setPrivate(n.id, !n.isPrivate));
    if (mounted) toast(context, l.tr(n.isPrivate ? 'private_off' : 'private_on'));
  }

  Future<String?> _pickType(String cur) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final t in kNoteTypes)
            ListTile(
              leading: Icon(typeIcon(t), color: AppColors.type(t)),
              title: Text(typeLabel(context.l, t)),
              trailing: t == cur ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, t),
            ),
        ],
      ),
    ),
  );

  Future<String?> _pickColor(String cur) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ColorPicker(value: cur, allowNone: true, onChanged: (c) => Navigator.pop(ctx, c)),
      ),
    ),
  );

  Future<void> _export(ExportFormat f) async {
    await _save();
    final ex = ref.read(exportServiceProvider);
    if (ex == null || !mounted) return;
    final l = context.l;
    await guard(context, () async {
      final file = await ex.exportNote(_title.text, DeltaDoc(List<Map<String, dynamic>>.from(_c!.document.toDelta().toJson())), f, rtlUi: l.ar, fallbackName: l.tr('untitled'));
      if (mounted) await shareOrSaveFile(context, file, subject: _title.text);
    });
  }

  void _info(Note n) {
    final l = context.l;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow(Icons.text_fields_rounded, l.tr('words'), '$_words'),
              _infoRow(Icons.abc_rounded, l.tr('characters'), '$_chars'),
              _infoRow(Icons.event_note_rounded, l.tr('created_at'), l.dateTime(n.createdAt)),
              _infoRow(Icons.edit_calendar_rounded, l.tr('updated_at'), l.dateTime(n.updatedAt)),
              _infoRow(typeIcon(n.type), l.tr('note_type'), typeLabel(l, n.type)),
              _infoRow(Icons.lock_rounded, l.tr('encryption'), l.tr(n.isPrivate ? 'encrypted_e2e' : 'not_encrypted')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData i, String k, String v) => ListTile(dense: true, leading: Icon(i), title: Text(k), trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.w700)));

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    ref.watch(notesProvider); // refresh flags after menu actions
    final c = _c;
    final n = _note;
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(l.tr(_error!))));
    }
    if (_locked && n != null) {
      return Scaffold(
        appBar: AppBar(title: Text(n.displayTitle(l.tr('untitled')))),
        body: EmptyState(
          icon: Icons.lock_rounded,
          title: l.tr('private_locked'),
          subtitle: l.tr('private_locked_sub'),
          action: FilledButton.icon(
            onPressed: () async {
              if (await ensureVaultUnlocked(context, ref)) _load();
            },
            icon: const Icon(Icons.lock_open_rounded),
            label: Text(l.tr('unlock')),
          ),
        ),
      );
    }
    if (c == null || n == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    final status = _saving ? l.tr('saving') : (_dirty ? l.tr('unsaved') : (_savedAt != null ? l.tr('saved') : ''));
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                Icon(typeIcon(n.type), color: AppColors.type(n.type), size: 20),
                const SizedBox(width: 6),
                Flexible(child: Text(typeLabel(l, n.type), style: const TextStyle(fontSize: 15))),
                if (n.isPrivate) ...[const SizedBox(width: 6), Icon(Icons.lock_rounded, size: 16, color: cs.primary)],
              ],
            ),
            actions: [
              IconButton(key: const Key('undo'), tooltip: l.tr('undo'), onPressed: c.hasUndo ? c.undo : null, icon: const Icon(Icons.undo_rounded)),
              IconButton(key: const Key('redo'), tooltip: l.tr('redo'), onPressed: c.hasRedo ? c.redo : null, icon: const Icon(Icons.redo_rounded)),
              IconButton(tooltip: l.tr(n.pinned ? 'unpin' : 'pin'), onPressed: () => _menu('pin'), icon: Icon(n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined)),
              PopupMenuButton<String>(
                key: const Key('note_menu'),
                onSelected: _menu,
                itemBuilder: (_) => [
                  _mi('fav', n.favorite ? Icons.star_rounded : Icons.star_border_rounded, l.tr(n.favorite ? 'unfavorite' : 'favorite')),
                  _mi('tags', Icons.sell_rounded, l.tr('tags')),
                  _mi('move', Icons.drive_file_move_rounded, l.tr('move_to_notebook')),
                  _mi('type', Icons.category_rounded, l.tr('note_type')),
                  _mi('color', Icons.palette_rounded, l.tr('note_color')),
                  _mi('dates', Icons.alarm_rounded, l.tr('dates_reminders')),
                  _mi('files', Icons.attach_file_rounded, l.tr('attachments')),
                  _mi('private', n.isPrivate ? Icons.lock_open_rounded : Icons.lock_rounded, l.tr(n.isPrivate ? 'make_public' : 'make_private')),
                  _mi('share', Icons.share_rounded, l.tr('share_collaborate')),
                  const PopupMenuDivider(),
                  for (final f in ExportFormat.values) _mi('export_${f.name}', Icons.ios_share_rounded, l.tr('export_as', {'f': f.ext.toUpperCase()})),
                  const PopupMenuDivider(),
                  _mi('template', Icons.bookmark_add_rounded, l.tr('save_as_template')),
                  _mi('duplicate', Icons.copy_rounded, l.tr('duplicate')),
                  _mi('info', Icons.info_outline_rounded, l.tr('note_info')),
                  _mi('archive', Icons.archive_rounded, l.tr(n.archived ? 'unarchive' : 'archive')),
                  _mi('trash', Icons.delete_outline_rounded, l.tr('move_to_trash')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                            child: TextField(
                              key: const Key('note_title'),
                              controller: _title,
                              style: TextStyle(fontSize: s.editorFontSize + 7, fontWeight: FontWeight.w800),
                              decoration: InputDecoration(
                                hintText: l.tr('title_hint'),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                              ),
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _focus.requestFocus(),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              child: QuillEditor(
                                key: const Key('note_body'),
                                controller: c,
                                focusNode: _focus,
                                scrollController: _scroll,
                                config: QuillEditorConfig(
                                  placeholder: l.tr('body_hint'),
                                  padding: const EdgeInsets.only(bottom: 80),
                                  embedBuilders: kEmbedBuilders,
                                  unknownEmbedBuilder: const UnknownEmbedBuilder(),
                                  customStyles: DefaultStyles(
                                    paragraph: DefaultTextBlockStyle(
                                      TextStyle(fontSize: s.editorFontSize, height: 1.6, color: cs.onSurface, fontFamily: s.font == 'system' ? null : 'Tajawal'),
                                      const HorizontalSpacing(0, 0),
                                      const VerticalSpacing(2, 2),
                                      const VerticalSpacing(0, 0),
                                      null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _statusBar(l, status, cs),
                _toolbar(l, c, cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String t) => PopupMenuItem(
    value: v,
    child: Row(children: [Icon(i, size: 20), const SizedBox(width: 12), Flexible(child: Text(t))]),
  );

  Widget _statusBar(L10n l, String status, ColorScheme cs) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    color: cs.surfaceContainer.withValues(alpha: 0.5),
    child: Row(
      children: [
        Text(l.tr('n_words', {'n': '$_words'}), key: const Key('word_count'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(width: 12),
        Text(l.tr('n_chars', {'n': '$_chars'}), key: const Key('char_count'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const Spacer(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Row(
            key: ValueKey(status),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.isNotEmpty) Icon(_dirty || _saving ? Icons.sync_rounded : Icons.cloud_done_rounded, size: 14, color: _dirty || _saving ? AppColors.warning : AppColors.success),
              const SizedBox(width: 4),
              Text(status, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _toolbar(L10n l, QuillController c, ColorScheme cs) => Material(
    color: cs.surfaceContainerLowest,
    elevation: 2,
    child: QuillSimpleToolbar(
      controller: c,
      config: QuillSimpleToolbarConfig(
        multiRowsDisplay: false,
        showFontFamily: false,
        showSubscript: false,
        showSuperscript: false,
        showSearchButton: false,
        showClearFormat: true,
        showDirection: true,
        showAlignmentButtons: true,
        showUndo: false,
        showRedo: false,
        showBackgroundColorButton: true,
        customButtons: [
          QuillToolbarCustomButtonOptions(icon: const Icon(Icons.image_rounded), tooltip: l.tr('insert_image'), onPressed: () => _insertImage()),
          if (PlatformSupport.camera) QuillToolbarCustomButtonOptions(icon: const Icon(Icons.photo_camera_rounded), tooltip: l.tr('camera'), onPressed: () => _insertImage(camera: true)),
          QuillToolbarCustomButtonOptions(icon: const Icon(Icons.attach_file_rounded), tooltip: l.tr('attach_file'), onPressed: () => _attachFile(PickKind.any)),
          QuillToolbarCustomButtonOptions(icon: const Icon(Icons.table_chart_rounded), tooltip: l.tr('insert_table'), onPressed: _insertTable),
          QuillToolbarCustomButtonOptions(icon: const Icon(Icons.horizontal_rule_rounded), tooltip: l.tr('insert_divider'), onPressed: () => insertEmbed(c, Embeds.divider, 'section')),
          QuillToolbarCustomButtonOptions(icon: const Icon(Icons.mic_rounded), tooltip: l.tr('record_voice'), onPressed: _record),
        ],
      ),
    ),
  );
}

/// Picks the note's tags (and creates new ones).
Future<void> editNoteTags(BuildContext context, WidgetRef ref, String noteId) async {
  final repo = ref.read(repoProvider);
  if (repo == null) return;
  final d = await ref.read(notesProvider.future);
  if (!context.mounted) return;
  final sel = {...d.tagsOfNote[noteId] ?? <String>{}};
  final tags = [...d.tags];
  final out = await showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('tags'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tags)
                    FilterChip(
                      label: Text('#${t.name}'),
                      selected: sel.contains(t.id),
                      selectedColor: AppColors.parse(t.color).withValues(alpha: 0.2),
                      onSelected: (v) => setS(() => v ? sel.add(t.id) : sel.remove(t.id)),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: Text(context.tr('new_tag')),
                    onPressed: () async {
                      final name = await promptText(ctx, context.tr('new_tag'));
                      if (name == null || name.trim().isEmpty) return;
                      final id = await repo.saveTag(name: name, color: AppColors.swatches[tags.length % AppColors.swatches.length]);
                      final r = await repo.store.get('tags', id);
                      setS(() {
                        if (r != null && !tags.any((t) => t.id == id)) tags.add(Tag(r));
                        sel.add(id);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: Text(context.tr('save'))),
            ],
          ),
        ),
      ),
    ),
  );
  if (out != null) await repo.setNoteTags(noteId, out);
}

/// Event (calendar), reminder and review dates of a note.
Future<void> editNoteDates(BuildContext context, WidgetRef ref, Note n) async {
  final repo = ref.read(repoProvider);
  if (repo == null) return;
  DateTime? ev = n.eventAt, rem = n.remindAt, rev = n.reviewAt;
  final l = context.l;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Widget row(String label, IconData icon, DateTime? v, void Function(DateTime?) set) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(v == null ? l.tr('not_set') : l.dateTime(v)),
          trailing: v == null ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setS(() => set(null))),
          onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(context: ctx, initialDate: v ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
            if (d == null || !ctx.mounted) return;
            final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(v ?? now.add(const Duration(hours: 1))));
            setS(() => set(DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0)));
          },
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(l.tr('event_date'), Icons.event_rounded, ev, (v) => ev = v),
              row(l.tr('reminder'), Icons.alarm_rounded, rem, (v) => rem = v),
              row(l.tr('review_date'), Icons.replay_rounded, rev, (v) => rev = v),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.tr('save')))),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (ok != true) return;
  await repo.update(n.id, {
    'event_at': ev == null ? null : isoUtc(ev!),
    'remind_at': rem == null ? null : isoUtc(rem!),
    'review_at': rev == null ? null : isoUtc(rev!),
  });
  if (rem != null || rev != null || ev != null) await ref.read(notificationServiceProvider).requestPermissions();
}

/// Files and recordings of a note: open, download, OCR, insert, delete.
Future<void> showNoteFiles(BuildContext context, WidgetRef ref, String noteId, {void Function(Attachment)? onInsert}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final d = ref.watch(notesProvider).value;
        final files = ref.read(fileServiceProvider);
        final l = ctx.l;
        if (d == null || files == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        final atts = d.attachmentsOf(noteId);
        final voices = d.voicesOf(noteId);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l.tr('attachments'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    PopupMenuButton<PickKind>(
                      icon: const Icon(Icons.add_circle_rounded),
                      onSelected: (k) => guard(ctx, () async {
                        final f = await files.pick(k);
                        if (f != null) await files.addPicked(f, noteId: noteId);
                      }),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: PickKind.image, child: Text(l.tr('pick_image'))),
                        PopupMenuItem(value: PickKind.document, child: Text(l.tr('pick_document'))),
                        PopupMenuItem(value: PickKind.audio, child: Text(l.tr('pick_audio'))),
                        PopupMenuItem(value: PickKind.any, child: Text(l.tr('pick_any'))),
                      ],
                    ),
                  ],
                ),
                if (atts.isEmpty && voices.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l.tr('no_attachments')))),
                for (final a in atts)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Icon(attIcon(a.fileType)),
                      title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([fileSize(a.size), if (a.ocrText.isNotEmpty) l.tr('text_read')].join(' · ')),
                      onTap: () => guard(ctx, () => files.open(a)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          switch (v) {
                            case 'insert':
                              onInsert?.call(a);
                              Navigator.pop(ctx);
                            case 'download':
                              await guard(ctx, () async {
                                final f = await files.plainCopy(a);
                                if (ctx.mounted) await shareOrSaveFile(ctx, f, subject: a.title);
                              });
                            case 'delete':
                              if (await confirm(ctx, l.tr('delete_file_confirm')) && ctx.mounted) await guard(ctx, () => files.remove(a));
                          }
                        },
                        itemBuilder: (_) => [
                          if (onInsert != null) PopupMenuItem(value: 'insert', child: Text(l.tr('insert_in_note'))),
                          PopupMenuItem(value: 'download', child: Text(l.tr('download'))),
                          PopupMenuItem(value: 'delete', child: Text(l.tr('delete'))),
                        ],
                      ),
                    ),
                  ),
                for (final v in voices)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const Icon(Icons.mic_rounded),
                      title: Text(v.title.isEmpty ? l.tr('voice_note') : v.title),
                      subtitle: Text(formatDuration(v.durationMs)),
                      onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => VoiceDetailScreen(voiceId: v.id))),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

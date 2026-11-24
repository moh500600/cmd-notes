import '../entities/entities.dart';
import 'folder_tree.dart';

/// Everything on this device for the signed-in user, loaded once per change.
class NotesData {
  final String uid;
  final List<Note> notes; // every note incl. archived/trashed (private ones still encrypted)
  final List<Notebook> notebooks;
  final List<Tag> tags;
  final List<NoteTag> noteTags;
  final List<NoteTemplate> templates;
  final List<Attachment> attachments;
  final List<VoiceRecording> voices;
  final List<JournalEntry> journal;
  final Profile? profile;

  NotesData({
    required this.uid,
    this.notes = const [],
    this.notebooks = const [],
    this.tags = const [],
    this.noteTags = const [],
    this.templates = const [],
    this.attachments = const [],
    this.voices = const [],
    this.journal = const [],
    this.profile,
  });

  late final FolderTree tree = FolderTree(notebooks);
  late final Map<String, Note> noteById = {for (final n in notes) n.id: n};
  late final Map<String, Tag> tagById = {for (final t in tags) t.id: t};

  late final Map<String, Set<String>> tagsOfNote = () {
    final m = <String, Set<String>>{};
    for (final nt in noteTags) {
      if (tagById.containsKey(nt.tagId)) (m[nt.noteId] ??= {}).add(nt.tagId);
    }
    return m;
  }();

  List<Tag> tagsOf(String noteId) => [for (final id in tagsOfNote[noteId] ?? const <String>{}) tagById[id]!]..sort((a, b) => a.name.compareTo(b.name));

  List<Note> get active => notes.where((n) => n.active).toList();
  List<Note> get archived => notes.where((n) => n.archived && !n.trashed).toList();
  List<Note> get trash => notes.where((n) => n.trashed).toList()..sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));
  List<Note> get pinned => sortNotes(active.where((n) => n.pinned));
  List<Note> get favorites => sortNotes(notes.where((n) => n.favorite && !n.trashed));
  List<Note> get recent => [...active]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  List<Note> get recentlyCreated => [...active]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Active notes with this tag (counts per tag ignore archived/trashed notes).
  int tagCount(String tagId) => active.where((n) => tagsOfNote[n.id]?.contains(tagId) ?? false).length;

  /// Notes in [notebookId] (optionally including its sub-folders).
  List<Note> inNotebook(String notebookId, {bool deep = false}) {
    final ids = deep ? tree.descendantsOf(notebookId) : {notebookId};
    return sortNotes(active.where((n) => n.notebookId != null && ids.contains(n.notebookId)));
  }

  int notebookCount(String id) => inNotebook(id, deep: true).length;

  List<Attachment> attachmentsOf(String noteId) => attachments.where((a) => a.noteId == noteId).toList();
  List<VoiceRecording> voicesOf(String noteId) => voices.where((v) => v.noteId == noteId).toList();

  /// Bytes of files this account holds (attachments + recordings).
  int get storageBytes => attachments.fold(0, (s, a) => s + a.size) + voices.fold(0, (s, v) => s + v.size);

  /// Notes and journal entries that belong to a calendar day (event, reminder, review, created).
  List<Note> notesOn(DateTime day) {
    bool same(DateTime? t) => t != null && t.year == day.year && t.month == day.month && t.day == day.day;
    return sortNotes(notes.where((n) => !n.trashed && (same(n.eventAt) || same(n.remindAt) || same(n.reviewAt) || same(n.createdAt))));
  }

  List<JournalEntry> journalOn(DateTime day) => journal.where((j) => j.date.year == day.year && j.date.month == day.month && j.date.day == day.day).toList();

  /// Notes with an event / reminder / review in the future, soonest first.
  List<(Note, DateTime)> upcoming(DateTime now) {
    final out = <(Note, DateTime)>[];
    for (final n in notes.where((n) => !n.trashed)) {
      for (final t in [n.eventAt, n.remindAt, n.reviewAt]) {
        if (t != null && t.isAfter(now)) out.add((n, t));
      }
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }
}

/// Pinned first, then most recently edited.
List<Note> sortNotes(Iterable<Note> it, {String by = 'updated'}) {
  final l = it.toList();
  l.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return switch (by) {
      'created' => b.createdAt.compareTo(a.createdAt),
      'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      _ => b.updatedAt.compareTo(a.updatedAt),
    };
  });
  return l;
}

/// Dashboard numbers (spec §2).
class DashboardStats {
  final int total, pinned, favorites, notebooks, tags, trashed, archived, voices, journal;
  final int storageBytes;
  const DashboardStats({
    required this.total,
    required this.pinned,
    required this.favorites,
    required this.notebooks,
    required this.tags,
    required this.trashed,
    required this.archived,
    required this.voices,
    required this.journal,
    required this.storageBytes,
  });

  factory DashboardStats.of(NotesData d) => DashboardStats(
    total: d.active.length,
    pinned: d.pinned.length,
    favorites: d.favorites.length,
    notebooks: d.notebooks.length,
    tags: d.tags.length,
    trashed: d.trash.length,
    archived: d.archived.length,
    voices: d.voices.length,
    journal: d.journal.length,
    storageBytes: d.storageBytes,
  );
}

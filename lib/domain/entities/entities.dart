import '../../core/utils/time.dart';
import '../services/delta_doc.dart';

/// Entities are thin, typed views over the device rows (one Map per row).
abstract class Rec {
  final Map<String, Object?> r;
  const Rec(this.r);
  String get id => r['id'] as String;
  String get userId => r['user_id'] as String? ?? '';
  DateTime get createdAt => parseIso(r['created_at']?.toString()) ?? DateTime.now();
  DateTime get updatedAt => parseIso(r['updated_at']?.toString()) ?? DateTime.now();
  String s(String k) => r[k]?.toString() ?? '';
  String? sn(String k) {
    final v = r[k]?.toString();
    return v == null || v.isEmpty ? null : v;
  }

  bool b(String k) => r[k] == 1 || r[k] == true;
  int i(String k) => (r[k] as num?)?.toInt() ?? 0;
  DateTime? t(String k) => parseIso(r[k]?.toString());
}

class Notebook extends Rec {
  const Notebook(super.r);
  String? get parentId => sn('parent_id');
  String get name => s('name');
  String get color => s('color');
  String get icon => s('icon');
  int get sortOrder => i('sort_order');
  bool get pinned => b('pinned');
  String get description => s('description');
  bool get isRoot => parentId == null;
}

class Tag extends Rec {
  const Tag(super.r);
  String get name => s('name');
  String get color => s('color');
}

class NoteTag extends Rec {
  const NoteTag(super.r);
  String get noteId => s('note_id');
  String get tagId => s('tag_id');
}

/// Note types (spec §6) — the key is stored, labels come from translations.
const kNoteTypes = ['text', 'study', 'work', 'meeting', 'personal', 'journal', 'idea', 'shopping', 'todo', 'code', 'voice'];

class Note extends Rec {
  const Note(super.r);
  String? get notebookId => sn('notebook_id');
  String get title => s('title');
  String get content => s('content');
  String get plainText => s('plain_text');
  String get type => s('note_type').isEmpty ? 'text' : s('note_type');
  String get templateKey => s('template_key');
  String get color => s('color');
  bool get pinned => b('pinned');
  bool get favorite => b('favorite');
  bool get archived => b('archived');
  DateTime? get trashedAt => t('trashed_at');
  bool get trashed => trashedAt != null;
  bool get isPrivate => b('is_private');
  String get cipherText => s('cipher_text');
  int get words => i('word_count');
  int get chars => i('char_count');
  DateTime? get eventAt => t('event_at');
  DateTime? get remindAt => t('remind_at');
  DateTime? get reviewAt => t('review_at');
  bool get active => !archived && !trashed;
  String displayTitle(String untitled) => title.trim().isNotEmpty ? title.trim() : untitled;
  DeltaDoc get doc => DeltaDoc.parse(content);
}

class NoteTemplate extends Rec {
  const NoteTemplate(super.r);
  String get name => s('name');
  String get type => s('note_type');
  String get icon => s('icon');
  String get description => s('description');
  String get content => s('content');
}

class Attachment extends Rec {
  const Attachment(super.r);
  String? get noteId => sn('note_id');
  String get ownerKind => s('owner_kind');
  String? get ownerId => sn('owner_id');
  String get title => s('title');
  String get fileType => s('file_type');
  String get mime => s('mime');
  int get size => i('size_bytes');
  String? get storagePath => sn('storage_path');
  String? get localPath => sn('local_path');
  String get ocrText => s('ocr_text');
}

class VoiceRecording extends Rec {
  const VoiceRecording(super.r);
  String? get noteId => sn('note_id');
  String? get notebookId => sn('notebook_id');
  String get title => s('title');
  String get description => s('description');
  int get durationMs => i('duration_ms');
  String get mime => s('mime');
  int get size => i('size_bytes');
  String? get storagePath => sn('storage_path');
  String? get localPath => sn('local_path');
  String get transcript => s('transcript');
  String get transcriptLang => s('transcript_lang');
}

class JournalEntry extends Rec {
  const JournalEntry(super.r);
  DateTime get date => parseDate(r['entry_date']?.toString()) ?? createdAt;
  String get title => s('title');
  String get content => s('content');
  String get plainText => s('plain_text');
  int? get mood => r['mood'] == null ? null : i('mood');
  String get achievements => s('achievements');
  String get thoughts => s('thoughts');
  String get goals => s('goals');
}

class Profile extends Rec {
  const Profile(super.r);
  String get displayName => s('display_name');
  String get vaultSalt => s('vault_salt');
  String get vaultCheck => s('vault_check');
  bool get hasVault => vaultSalt.isNotEmpty && vaultCheck.isNotEmpty;
}

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/entities.dart';
import '../repositories/notes_repository.dart';
import '../security/field_cipher.dart';

/// File type from a file name's extension.
String fileTypeOf(String name) {
  final e = p.extension(name).toLowerCase().replaceFirst('.', '');
  return switch (e) {
    'pdf' => 'pdf',
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'heic' || 'bmp' => 'image',
    'doc' || 'docx' || 'odt' || 'rtf' => 'word',
    'xls' || 'xlsx' || 'ods' || 'csv' => 'excel',
    'ppt' || 'pptx' || 'odp' => 'powerpoint',
    'mp3' || 'm4a' || 'aac' || 'wav' || 'ogg' || 'opus' || 'flac' => 'audio',
    'txt' || 'md' || 'html' || 'htm' => 'text',
    _ => 'other',
  };
}

String mimeOf(String name) => switch (p.extension(name).toLowerCase()) {
  '.pdf' => 'application/pdf',
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.webp' => 'image/webp',
  '.gif' => 'image/gif',
  '.heic' => 'image/heic',
  '.txt' => 'text/plain',
  '.md' => 'text/markdown',
  '.html' || '.htm' => 'text/html',
  '.csv' => 'text/csv',
  '.doc' => 'application/msword',
  '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls' => 'application/vnd.ms-excel',
  '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt' => 'application/vnd.ms-powerpoint',
  '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.mp3' => 'audio/mpeg',
  '.m4a' || '.aac' => 'audio/mp4',
  '.wav' => 'audio/wav',
  '.ogg' || '.opus' => 'audio/ogg',
  _ => 'application/octet-stream',
};

const kMaxFileBytes = 50 * 1024 * 1024; // the bucket's limit

enum PickKind { image, document, audio, any, importable }

const kDocExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'txt', 'md', 'rtf', 'odt', 'ods', 'odp', 'zip'];
const kAudioExtensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'];

/// Attachments and voice recordings.
/// * On the device they are stored ENCRYPTED (AES-256-GCM, key in the OS key store);
///   opening one writes a temporary plain copy to the app's cache, cleared on start.
class FileService {
  final NotesRepository repo;
  final AesGcmFieldCipher? cipher;
  FileService(this.repo, this.cipher);

  static Future<Directory> filesDir() async {
    final d = Directory(p.join((await getApplicationSupportDirectory()).path, 'notes_files'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> tempDir() async {
    final d = Directory(p.join((await getTemporaryDirectory()).path, 'notes_open'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Removes plain copies left from opening files.
  static Future<void> clearTemp() async {
    try {
      final d = Directory(p.join((await getTemporaryDirectory()).path, 'notes_open'));
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  static String ext(String name) {
    final e = p.extension(name).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(e) ? e : '';
  }

  Future<File> _blob(String id) async => File(p.join((await filesDir()).path, '$id.bin'));

  Uint8List _seal(Uint8List b) => cipher == null ? b : cipher!.encryptBytes(b);
  Uint8List _open(Uint8List b) => cipher == null ? b : cipher!.decryptBytes(b);

  Future<PlatformFile?> pick(PickKind kind) => switch (kind) {
    PickKind.image => FilePicker.pickFile(type: FileType.image),
    PickKind.document => FilePicker.pickFile(type: FileType.custom, allowedExtensions: kDocExtensions),
    PickKind.audio => FilePicker.pickFile(type: FileType.custom, allowedExtensions: kAudioExtensions),
    PickKind.any => FilePicker.pickFile(type: FileType.any),
    PickKind.importable => FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['txt', 'md', 'markdown', 'html', 'htm']),
  };

  Future<String> addPicked(PlatformFile f, {String? noteId, String ownerKind = 'note', String? ownerId}) async =>
      addBytes(f.name, await f.readAsBytes(), noteId: noteId, ownerKind: ownerKind, ownerId: ownerId);

  Future<String> addBytes(String name, Uint8List bytes, {String? noteId, String ownerKind = 'note', String? ownerId, String? title}) async {
    if (bytes.isEmpty) throw const AppException('err_file_missing');
    if (bytes.length > kMaxFileBytes) throw const AppException('err_file_too_big');
    final id = newId();
    await (await _blob(id)).writeAsBytes(_seal(bytes), flush: true);
    await repo.save('attachments', {
      'id': id,
      'note_id': noteId,
      'owner_kind': ownerKind,
      'owner_id': ownerId ?? noteId,
      'title': (title == null || title.trim().isEmpty) ? p.basename(name) : title.trim(),
      'file_type': fileTypeOf(name),
      'mime': mimeOf(name),
      'size_bytes': bytes.length,
      'local_path': '$id${ext(name)}',
    });
    if (noteId != null) await repo.reindexNote(noteId);
    return id;
  }

  /// Stores a finished recording (moved from the recorder's temp file). Returns its id.
  Future<String> addVoice(File recorded, {required String title, int durationMs = 0, String? noteId, String? notebookId, String description = ''}) async {
    final bytes = await recorded.readAsBytes();
    if (bytes.isEmpty) throw const AppException('err_file_missing');
    if (bytes.length > kMaxFileBytes) throw const AppException('err_file_too_big');
    final id = newId();
    await (await _blob(id)).writeAsBytes(_seal(bytes), flush: true);
    try {
      await recorded.delete();
    } catch (_) {}
    final e = ext(recorded.path).isEmpty ? '.m4a' : ext(recorded.path);
    await repo.saveVoice(id, {
      'title': title,
      'description': description,
      'duration_ms': durationMs,
      'mime': mimeOf('x$e'),
      'size_bytes': bytes.length,
      'local_path': '$id$e',
      'note_id': noteId,
      'notebook_id': notebookId,
    });
    return id;
  }

  Future<Uint8List> _bytes(String id) async {
    final f = await _blob(id);
    if (await f.exists()) return _open(await f.readAsBytes());
    throw const AppException('err_file_missing');
  }

  /// The file's plain bytes: from the device.
  Future<Uint8List> bytes(Attachment a) => _bytes(a.id);
  Future<Uint8List> voiceBytes(VoiceRecording v) => _bytes(v.id);

  Future<bool> isLocal(String id) async => (await _blob(id)).exists();

  /// A plain temporary copy (for the system viewer / the audio player / sharing).
  Future<File> plainCopy(Attachment a) async {
    final tmp = File(p.join((await tempDir()).path, '${a.id}_${_safeName(a.title, a.localPath)}'));
    if (!await tmp.exists()) await tmp.writeAsBytes(await bytes(a), flush: true);
    return tmp;
  }

  Future<File> voiceFile(VoiceRecording v) async {
    final tmp = File(p.join((await tempDir()).path, '${v.id}${ext(v.localPath ?? '.m4a').isEmpty ? '.m4a' : ext(v.localPath!)}'));
    if (!await tmp.exists()) await tmp.writeAsBytes(await voiceBytes(v), flush: true);
    return tmp;
  }

  static String _safeName(String title, String? local) {
    var n = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (ext(n).isEmpty && local != null) n += ext(local);
    return n;
  }

  Future<void> open(Attachment a) async {
    final tmp = await plainCopy(a);
    final res = await OpenFilex.open(tmp.path);
    if (res.type != ResultType.done) throw AppException('err_open_file', res.message);
  }

  Future<void> remove(Attachment a) async {
    final f = await _blob(a.id);
    if (await f.exists()) await f.delete();
    await repo.delete('attachments', a.id);
    if (a.noteId != null) await repo.reindexNote(a.noteId!);
  }

  Future<void> removeVoice(VoiceRecording v) async {
    final f = await _blob(v.id);
    if (await f.exists()) await f.delete();
    await repo.deleteVoiceRow(v.id);
  }

  /// Deletes every local file (used when wiping the device).
  static Future<void> wipeLocal() async {
    final d = await filesDir();
    if (await d.exists()) await d.delete(recursive: true);
    await clearTemp();
  }

  /// Bytes used on this device by files.
  static Future<int> localBytes() async {
    var n = 0;
    final d = await filesDir();
    await for (final f in d.list()) {
      if (f is File) n += await f.length();
    }
    return n;
  }
}

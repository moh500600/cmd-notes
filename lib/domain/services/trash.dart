import '../../core/utils/time.dart';
import '../entities/entities.dart';

/// Lifecycle of a note: active → (archived) → trash → restored | permanently deleted.
/// Notes stay in the trash for [retentionDays], then are deleted for good.
class TrashPolicy {
  static const retentionDays = 30;

  static Map<String, Object?> moveToTrash(DateTime now) => {'trashed_at': isoUtc(now), 'pinned': 0};
  static Map<String, Object?> restore() => {'trashed_at': null};
  static Map<String, Object?> archive(bool on) => {'archived': on ? 1 : 0, if (on) 'pinned': 0};

  /// Days left before a trashed note is deleted for good (0 = due now).
  static int daysLeft(Note n, DateTime now) {
    final t = n.trashedAt;
    if (t == null) return retentionDays;
    final left = retentionDays - now.difference(t).inDays;
    return left < 0 ? 0 : left;
  }

  static bool expired(Note n, DateTime now) => n.trashed && now.difference(n.trashedAt!).inDays >= retentionDays;
}

/// Which list a note appears in.
enum NoteBucket { active, archived, trash }

NoteBucket bucketOf(Note n) => n.trashed ? NoteBucket.trash : (n.archived ? NoteBucket.archived : NoteBucket.active);

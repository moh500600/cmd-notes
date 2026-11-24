import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/l10n/l10n.dart';
import '../../core/utils/ids.dart';
import '../../data/db/local_store.dart';
import '../../data/db/search_index.dart';
import '../../data/repositories/notes_repository.dart';
import '../../data/security/field_cipher.dart';
import '../../data/security/key_vault.dart';
import '../../data/services/export_service.dart';
import '../../data/services/local_session.dart';
import '../../data/services/file_service.dart';
import '../../data/services/lock_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/settings_repository.dart';
import '../../domain/services/notes_data.dart';
import '../../domain/services/reminders.dart';

// ------------------------------------------------------------------ roots (overridden in main)
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError('databaseProvider'));
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider'));

/// AES-256-GCM for files and the journal on this device (null only in some tests).
final cipherProvider = Provider<AesGcmFieldCipher?>((ref) => null);
final keyLocationProvider = Provider<KeyLocation>((ref) => KeyLocation.memory);

/// The full-text index (initialised in main; tests create their own).
final searchIndexProvider = Provider<SearchIndex>((ref) => SearchIndex(ref.watch(databaseProvider)));

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());
final lockServiceProvider = Provider<LockService>((ref) => LockService(ref.watch(prefsProvider)));

/// Bumped on every local write, so the data below reloads.
class Revision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final revisionProvider = NotifierProvider<Revision, int>(Revision.new);

final storeProvider = Provider<LocalStore>((ref) {
  final store = LocalStore(ref.watch(databaseProvider), cipher: ref.watch(cipherProvider));
  store.onChange = (_) {
    ref.read(revisionProvider.notifier).bump();
  };
  return store;
});

// ------------------------------------------------------------------ settings
class SettingsNotifier extends Notifier<AppSettings> {
  late SettingsRepository _repo;
  @override
  AppSettings build() {
    _repo = SettingsRepository(ref.watch(prefsProvider));
    return _repo.load();
  }

  Future<void> update(AppSettings s) async {
    state = s;
    await _repo.save(s);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ------------------------------------------------------------------ session
class SessionNotifier extends Notifier<AppSession?> {
  @override
  AppSession? build() => const AppSession(kLocalUid);

  /// Erases all notes and files on this device.
  Future<void> wipeDevice() async {
    final s = state;
    await ref.read(notificationServiceProvider).cancelAll();
    ref.read(repoProvider)?.lockVault();
    if (s != null) {
      await ref.read(storeProvider).wipe(s.uid);
      await FileService.wipeLocal();
    }
    ref.invalidate(revisionProvider);
    ref.read(revisionProvider.notifier).bump();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, AppSession?>(SessionNotifier.new);

// ------------------------------------------------------------------ data
final repoProvider = Provider<NotesRepository?>((ref) {
  final s = ref.watch(sessionProvider);
  return s == null ? null : NotesRepository(ref.watch(storeProvider), ref.watch(searchIndexProvider), s.uid);
});

/// Whether the private-notes vault is unlocked (bumped when it locks/unlocks).
class VaultState extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(repoProvider);
    return ref.read(repoProvider)?.vault != null;
  }

  void refresh() => state = ref.read(repoProvider)?.vault != null;
}

final vaultProvider = NotifierProvider<VaultState, bool>(VaultState.new);

/// Everything the user has on this device (reloaded after every write or sync).
final notesProvider = FutureProvider<NotesData>((ref) async {
  ref.watch(revisionProvider);
  final repo = ref.watch(repoProvider);
  if (repo == null) return NotesData(uid: '');
  return repo.load();
});

final fileServiceProvider = Provider<FileService?>((ref) {
  final repo = ref.watch(repoProvider);
  return repo == null ? null : FileService(repo, ref.watch(cipherProvider));
});

final exportServiceProvider = Provider<ExportService?>((ref) {
  final repo = ref.watch(repoProvider);
  return repo == null ? null : ExportService(repo, rootBundle.load);
});

/// A random id for this installation (for "devices / sessions").
String deviceId(SharedPreferences prefs) {
  var id = prefs.getString('device_id');
  if (id == null) {
    id = newId();
    prefs.setString('device_id', id);
  }
  return id;
}

// ------------------------------------------------------------------ app lock
class LockState extends Notifier<bool> {
  DateTime? _pausedAt;
  @override
  bool build() {
    final s = ref.read(settingsProvider);
    return s.appLock && ref.read(lockServiceProvider).hasPin; // locked at start
  }

  void unlock() => state = false;
  void lockNow() {
    final s = ref.read(settingsProvider);
    if (s.appLock && ref.read(lockServiceProvider).hasPin) state = true;
  }

  void paused() => _pausedAt = DateTime.now();
  void resumed() {
    final s = ref.read(settingsProvider);
    final p = _pausedAt;
    _pausedAt = null;
    if (p != null && s.appLock && DateTime.now().difference(p).inSeconds >= s.lockAfterSec) lockNow();
  }
}

final lockProvider = NotifierProvider<LockState, bool>(LockState.new);

// ------------------------------------------------------------------ reminders
/// Re-plans every OS reminder from the current data (called after changes).
Future<void> rescheduleReminders(WidgetRef ref, NotesData d) async {
  final s = ref.read(settingsProvider);
  final l = L10n(s.lang);
  final plan = planReminders(d, s.reminders, DateTime.now(), untitled: l.tr('untitled'));
  String title(PlannedReminder p) => switch (p.kind) {
    ReminderKind.review => l.tr('notif_review'),
    ReminderKind.remind => l.tr('notif_reminder'),
    ReminderKind.event => l.tr('notif_event'),
    ReminderKind.journal => l.tr('notif_journal'),
  };
  String body(PlannedReminder p) => p.kind == ReminderKind.journal ? l.tr('notif_journal_body') : (s.hidePreviews || p.title.isEmpty ? l.tr('notif_open_app') : p.title);
  await ref.read(notificationServiceProvider).reschedule([
    for (final p in plan) ScheduledAlert(p.id, p.when, title(p), body(p), repeat: p.daily ? DateTimeComponents.time : null),
  ]);
}

/// Shows an AppException-aware error message.
String errorText(BuildContext context, Object e) {
  final s = e.toString();
  final key = s.contains(':') ? s.substring(0, s.indexOf(':')) : s;
  final t = context.tr(key);
  return t == key ? s : (s.contains(':') ? '$t (${s.substring(s.indexOf(':') + 1).trim()})' : t);
}

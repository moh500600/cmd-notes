import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/desktop_files.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/text_tools.dart';
import '../../../core/utils/time.dart';
import '../../../core/utils/validators.dart';
import '../../../data/security/key_vault.dart';
import '../../../data/services/export_service.dart';
import '../../../data/services/file_service.dart';
import '../../../data/services/settings_repository.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../editor/vault_dialogs.dart';
import '../lock/lock_screen.dart';
import '../notes/notes_list_screen.dart';
import '../templates/templates_screen.dart';
import 'demo_data.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    final vaultOpen = ref.watch(vaultProvider);
    final set = ref.read(settingsProvider.notifier);
    void put(AppSettings n) => set.update(n);
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    Widget nav(IconData i, String k, VoidCallback f, {String? sub}) => ListTile(leading: Icon(i), title: Text(l.tr(k)), subtitle: sub == null ? null : Text(sub), trailing: const Icon(Icons.chevron_right_rounded), onTap: f);
    Widget choice<T>(IconData i, String k, T value, List<(T, String)> opts, ValueChanged<T> on) => ListTile(
      leading: Icon(i),
      title: Text(l.tr(k)),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox(),
        items: [for (final (v, t) in opts) DropdownMenuItem(value: v, child: Text(t))],
        onChanged: (v) => v == null ? null : on(v),
      ),
    );
    final r = s.reminders;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('settings'))),
      body: PageList(
        children: [
          SectionTitle(l.tr('appearance'), icon: Icons.palette_rounded),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  choice(Icons.language_rounded, 'language', s.lang, const [('ar', 'العربية'), ('en', 'English')], (v) => put(s.copyWith(lang: v))),
                  choice(Icons.dark_mode_rounded, 'theme', s.theme, [(ThemeMode.system, l.tr('theme_system')), (ThemeMode.light, l.tr('theme_light')), (ThemeMode.dark, l.tr('theme_dark'))], (v) => put(s.copyWith(theme: v))),
                  choice(Icons.font_download_rounded, 'font', s.font, [('tajawal', 'Tajawal'), ('system', l.tr('system_font'))], (v) => put(s.copyWith(font: v))),
                  ListTile(leading: const Icon(Icons.color_lens_rounded), title: Text(l.tr('accent_color'))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in AppColors.accents)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => put(s.copyWith(accent: a)),
                            child: CircleAvatar(radius: 17, backgroundColor: Color(a), child: s.accent == a ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null),
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.format_size_rounded),
                    title: Text(l.tr('text_size')),
                    subtitle: Slider(value: s.textScale, min: 0.85, max: 1.4, divisions: 11, label: '${(s.textScale * 100).round()}%', onChanged: (v) => put(s.copyWith(textScale: v))),
                  ),
                  SwitchListTile(secondary: const Icon(Icons.grid_view_rounded), value: s.gridView, onChanged: (v) => put(s.copyWith(gridView: v)), title: Text(l.tr('grid_view'))),
                ],
              ),
            ),
          ),
          SectionTitle(l.tr('editor'), icon: Icons.edit_note_rounded),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: Text(l.tr('editor_font_size')),
                  subtitle: Slider(value: s.editorFontSize, min: 13, max: 26, divisions: 13, label: '${s.editorFontSize.round()}', onChanged: (v) => put(s.copyWith(editorFontSize: v))),
                ),
                choice(Icons.save_rounded, 'autosave_delay', s.autosaveMs, [for (final ms in [500, 1000, 2000, 5000]) (ms, l.tr('n_seconds', {'n': (ms / 1000).toString().replaceAll('.0', '')}))], (v) => put(s.copyWith(autosaveMs: v))),
                nav(Icons.dashboard_customize_rounded, 'templates', () => push(const TemplatesScreen())),
              ],
            ),
          ),
          SectionTitle(l.tr('voice_notes'), icon: Icons.mic_rounded),
          Card(
            child: Column(
              children: [
                choice(Icons.high_quality_rounded, 'record_quality', s.recordQuality, [('high', l.tr('quality_high')), ('normal', l.tr('quality_normal')), ('low', l.tr('quality_low'))], (v) => put(s.copyWith(recordQuality: v))),
              ],
            ),
          ),
          SectionTitle(l.tr('notifications'), icon: Icons.notifications_rounded),
          Card(
            child: Column(
              children: [
                SwitchListTile(secondary: const Icon(Icons.notifications_active_rounded), value: r.enabled, onChanged: (v) => put(s.copyWith(reminders: r.copyWith(enabled: v))), title: Text(l.tr('note_reminders')), subtitle: Text(l.tr('note_reminders_sub'))),
                choice(Icons.timer_rounded, 'event_lead', r.eventLeadMin, [for (final m in [0, 10, 30, 60, 1440]) (m, m == 0 ? l.tr('at_time') : (m == 1440 ? l.tr('one_day_before') : l.tr('n_min_before', {'n': '$m'})))], (v) => put(s.copyWith(reminders: r.copyWith(eventLeadMin: v)))),
                SwitchListTile(secondary: const Icon(Icons.auto_stories_rounded), value: r.journalDaily, onChanged: (v) => put(s.copyWith(reminders: r.copyWith(journalDaily: v))), title: Text(l.tr('journal_reminder'))),
                if (r.journalDaily)
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(l.tr('at_time')),
                    trailing: SizedBox(width: 130, child: TimeField(label: '', minutes: r.journalMinute, compact: true, onChanged: (v) => put(s.copyWith(reminders: r.copyWith(journalMinute: v ?? r.journalMinute))))),
                  ),
                SwitchListTile(secondary: const Icon(Icons.visibility_off_rounded), value: s.hidePreviews, onChanged: (v) => put(s.copyWith(hidePreviews: v)), title: Text(l.tr('hide_previews')), subtitle: Text(l.tr('hide_previews_sub'))),
                ListTile(
                  leading: const Icon(Icons.notifications_rounded),
                  title: Text(l.tr('allow_notifications')),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      final ok = await ref.read(notificationServiceProvider).requestPermissions();
                      if (context.mounted) toast(context, l.tr(ok ? 'notifications_on' : 'notifications_denied'));
                    },
                    child: Text(l.tr('allow')),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(l.tr('privacy_security'), icon: Icons.shield_outlined),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('app_lock'),
                  secondary: const Icon(Icons.pin_rounded),
                  value: s.appLock && ref.read(lockServiceProvider).hasPin,
                  title: Text(l.tr('app_lock')),
                  subtitle: Text(l.tr('app_lock_sub')),
                  onChanged: (v) async {
                    if (v) {
                      if (await setupPin(context, ref)) put(s.copyWith(appLock: true));
                    } else {
                      if (!await verifyIdentity(context, ref)) return;
                      await ref.read(lockServiceProvider).clearPin();
                      put(s.copyWith(appLock: false, journalLock: false));
                    }
                  },
                ),
                if (s.appLock) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    value: s.biometric,
                    title: Text(l.tr('biometric')),
                    onChanged: (v) async {
                      if (v && !await ref.read(lockServiceProvider).biometricAvailable()) {
                        if (context.mounted) toast(context, l.tr('biometric_unavailable'));
                        return;
                      }
                      put(s.copyWith(biometric: v));
                    },
                  ),
                  choice(Icons.lock_clock_rounded, 'lock_after', s.lockAfterSec, [(0, l.tr('immediately')), (30, l.tr('n_seconds', {'n': '30'})), (60, l.tr('n_min', {'n': '1'})), (300, l.tr('n_min', {'n': '5'})), (900, l.tr('n_min', {'n': '15'}))], (v) => put(s.copyWith(lockAfterSec: v))),
                  SwitchListTile(secondary: const Icon(Icons.auto_stories_rounded), value: s.journalLock, onChanged: (v) => put(s.copyWith(journalLock: v)), title: Text(l.tr('journal_lock')), subtitle: Text(l.tr('journal_lock_sub'))),
                ],
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_rounded),
                  title: Text(l.tr('private_vault')),
                  subtitle: Text(l.tr(vaultOpen ? 'vault_open' : 'vault_closed')),
                  trailing: vaultOpen
                      ? TextButton(
                          onPressed: () {
                            ref.read(repoProvider)?.lockVault();
                            ref.read(vaultProvider.notifier).refresh();
                          },
                          child: Text(l.tr('lock')),
                        )
                      : TextButton(onPressed: () => ensureVaultUnlocked(context, ref), child: Text(l.tr('unlock'))),
                ),
                SwitchListTile(secondary: const Icon(Icons.auto_awesome_rounded), value: s.aiUseNotes, onChanged: (v) => put(s.copyWith(aiUseNotes: v)), title: Text(l.tr('ai_use_notes')), subtitle: Text(l.tr('ai_use_notes_sub'))),
                nav(Icons.verified_user_rounded, 'encryption_status', () => push(const PrivacyScreen())),
              ],
            ),
          ),
          SectionTitle(l.tr('backup_export'), icon: Icons.save_alt_rounded),
          Card(
            child: Column(
              children: [
                ListTile(key: const Key('backup'), leading: const Icon(Icons.backup_rounded), title: Text(l.tr('backup')), subtitle: Text(l.tr('backup_sub')), onTap: () => _backup(context, ref)),
                ListTile(leading: const Icon(Icons.restore_rounded), title: Text(l.tr('restore_backup')), onTap: () => _restore(context, ref)),
                ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: Text(l.tr('export_all_pdf')), subtitle: Text(l.tr('export_all_pdf_sub')), onTap: () => _exportAll(context, ref)),
              ],
            ),
          ),
          SectionTitle(l.tr('storage'), icon: Icons.sd_storage_rounded),
          Card(
            child: Column(
              children: [
                FutureBuilder<int>(
                  future: FileService.localBytes(),
                  builder: (_, snap) => ListTile(leading: const Icon(Icons.folder_rounded), title: Text(l.tr('on_device')), trailing: Text(snap.hasData ? fileSize(snap.data!) : '…')),
                ),
                nav(Icons.archive_rounded, 'archive', () => push(const NotesListScreen(filter: NoteFilter('archived')))),
                nav(Icons.delete_rounded, 'trash', () => push(const NotesListScreen(filter: NoteFilter('trash')))),
              ],
            ),
          ),
          SectionTitle(l.tr('your_data'), icon: Icons.delete_outline_rounded),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phonelink_erase_rounded, color: AppColors.danger),
                  title: Text(l.tr('delete_local_data'), style: const TextStyle(color: AppColors.danger)),
                  subtitle: Text(l.tr('delete_local_guest_sub')),
                  onTap: () => _deleteLocal(context, ref),
                ),
              ],
            ),
          ),
          SectionTitle(l.tr('demo'), icon: Icons.science_rounded),
          Card(
            child: ListTile(
              key: const Key('load_demo'),
              leading: const Icon(Icons.auto_awesome_motion_rounded),
              title: Text(l.tr('load_demo')),
              subtitle: Text(l.tr('load_demo_sub')),
              onTap: () async {
                final repo = ref.read(repoProvider);
                if (repo == null || !await confirm(context, l.tr('load_demo_confirm'), danger: false)) return;
                await loadDemoData(repo, ar: l.ar);
                if (context.mounted) toast(context, l.tr('demo_loaded'));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text('${l.tr('app_name')} · 1.0.0', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
    final ex = ref.read(exportServiceProvider);
    final repo = ref.read(repoProvider);
    if (ex == null || repo == null) return;
    final l = context.l;
    await guard(context, () async {
      final d = await repo.load();
      final list = [for (final n in d.active.where((n) => !n.isPrivate)) (n.displayTitle(l.tr('untitled')), n.doc)];
      if (list.isEmpty) {
        if (context.mounted) toast(context, l.tr('nothing_to_export'));
        return;
      }
      final bytes = await ex.pdf(list, rtlUi: l.ar);
      final f = await ex.writeOut('notes_${dateKey(DateTime.now())}.pdf', bytes);
      if (context.mounted) await shareOrSaveFile(context, f, subject: l.tr('export_all_pdf'));
    });
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final e = ref.read(exportServiceProvider);
    if (e == null) return;
    final c1 = TextEditingController(), c2 = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.tr('backup')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.tr('backup_password_hint')),
            TextField(
              controller: c1,
              obscureText: true,
              decoration: InputDecoration(labelText: l.tr('backup_password')),
            ),
            TextField(
              controller: c2,
              obscureText: true,
              decoration: InputDecoration(labelText: l.tr('confirm_password')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.tr('create'))),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    if (c1.text != c2.text) return toast(context, l.tr('v_password_match'));
    if (c1.text.isNotEmpty && c1.text.length < 8) return toast(context, l.tr('v_backup_password'));
    if (c1.text.isEmpty && !await confirm(context, l.tr('backup_plain_warning'), okLabel: l.tr('continue'), danger: true)) return;
    if (!context.mounted) return;
    await guard(context, () async {
      final f = await e.backup(password: c1.text.isEmpty ? null : c1.text);
      if (context.mounted) await shareOrSaveFile(context, f, subject: l.tr('backup'));
    });
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final ex = ref.read(exportServiceProvider);
    if (ex == null) return;
    final f = await pickFileBytes();
    if (f == null || !context.mounted) return;
    final text = utf8.decode(f);
    String? pw;
    if (ExportService.isEncryptedBackup(text)) {
      final c = TextEditingController();
      pw = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l.tr('backup_password')),
          content: TextField(controller: c, obscureText: true, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(l.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(l.tr('ok'))),
          ],
        ),
      );
      if (pw == null) return;
    }
    if (!context.mounted || !await confirm(context, l.tr('restore_confirm'), danger: false)) return;
    if (!context.mounted) return;
    await guard(context, () async {
      final n = await ex.restore(text, password: pw);
      if (context.mounted) toast(context, l.tr('restored_n', {'n': '$n'}));
    });
  }

  Future<bool> _typed(BuildContext context, String message, String word) async {
    final l = context.l;
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.tr('are_you_sure')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 10),
            Text(l.tr('type_to_confirm', {'w': word})),
            TextField(controller: c, autofocus: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(d, true),
            child: Text(l.tr('delete')),
          ),
        ],
      ),
    );
    return ok == true && c.text.trim().toUpperCase() == word;
  }

  Future<void> _deleteLocal(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    if (!await _typed(context, l.tr('delete_local_guest_sub'), 'DELETE') || !context.mounted) return;
    await guard(context, () async {
      await ref.read(sessionProvider.notifier).wipeDevice();
      await FileService.clearTemp();
    });
  }
}

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final loc = ref.watch(keyLocationProvider);
    final on = ref.watch(cipherProvider) != null;
    Widget item(bool good, String k) => ListTile(
      leading: Icon(good ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: good ? AppColors.success : AppColors.warning),
      title: Text(l.tr(k)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('encryption_status'))),
      body: PageList(
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.key_rounded, color: loc == KeyLocation.secureStorage ? AppColors.success : AppColors.warning),
              title: Text(l.tr('key_location')),
              subtitle: Text(l.tr('key_${loc.name}')),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                item(on, 'enc_fields'),
                item(on, 'enc_files'),
                item(true, 'enc_private_notes'),
                item(true, 'enc_transport'),
                item(false, 'enc_server'),
                item(true, 'enc_rls'),
                item(true, 'enc_backup'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

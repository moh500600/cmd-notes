import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/desktop_files.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Shares a note or a notebook as a file (no server): the file goes out through
/// the system share sheet and the other person imports it. Private notes are never included.
Future<void> showShareSheet(BuildContext context, WidgetRef ref, {String? noteId, String? notebookId, required String title}) async {
  final e = ref.read(exportServiceProvider);
  if (e == null) return;
  final l = context.l;
  await guard(context, () async {
    final f = await e.shareFile(noteId: noteId, notebookId: notebookId);
    if (context.mounted) await shareOrSaveFile(context, f, subject: title.isEmpty ? l.tr('app_name') : title);
  });
}

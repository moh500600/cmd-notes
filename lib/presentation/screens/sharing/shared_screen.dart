import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/desktop_files.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Import a note or notebook someone sent you as a file (merged into your notes).
class SharedScreen extends ConsumerWidget {
  const SharedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('shared'))),
      body: PageList(
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(l.tr('share_file_note')))),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('import_shared'),
            icon: const Icon(Icons.file_open_rounded),
            label: Text(l.tr('share_import_btn')),
            onPressed: () async {
              final ex = ref.read(exportServiceProvider);
              if (ex == null) return;
              final bytes = await pickFileBytes();
              if (bytes == null || !context.mounted) return;
              await guard(context, () async {
                final n = await ex.restore(utf8.decode(bytes));
                if (context.mounted) toast(context, l.tr('restored_n', {'n': '$n'}));
              });
            },
          ),
        ],
      ),
    );
  }
}

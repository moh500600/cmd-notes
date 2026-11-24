import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Makes sure the private-notes vault is unlocked: creates it (first time) or asks for the passphrase.
Future<bool> ensureVaultUnlocked(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repoProvider);
  if (repo == null) return false;
  if (repo.vault != null) return true;
  final p = await repo.profile();
  if (!context.mounted) return false;
  final l = context.l;
  final creating = p == null || !p.hasVault;
  final pass = TextEditingController(), pass2 = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        icon: const Icon(Icons.enhanced_encryption_rounded),
        title: Text(l.tr(creating ? 'vault_create' : 'vault_unlock')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.tr(creating ? 'vault_create_sub' : 'vault_unlock_sub'), style: const TextStyle(fontSize: 13.5)),
              const SizedBox(height: 12),
              TextField(
                key: const Key('vault_pass'),
                controller: pass,
                obscureText: true,
                autofocus: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: l.tr('passphrase')),
              ),
              if (creating) ...[
                const SizedBox(height: 8),
                TextField(controller: pass2, obscureText: true, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: l.tr('confirm_passphrase'))),
              ],
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.red))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.tr('cancel'))),
          FilledButton(
            onPressed: () async {
              if (creating) {
                if (pass.text.length < 6) return setS(() => err = l.tr('err_passphrase_short'));
                if (pass.text != pass2.text) return setS(() => err = l.tr('passphrase_mismatch'));
                await repo.createVault(pass.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                final good = await repo.unlockVault(pass.text);
                if (!good) return setS(() => err = l.tr('err_vault_wrong'));
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
            },
            child: Text(l.tr(creating ? 'create' : 'unlock')),
          ),
        ],
      ),
    ),
  );
  ref.read(vaultProvider.notifier).refresh();
  if (ok == true && context.mounted) toast(context, l.tr(creating ? 'vault_created' : 'vault_unlocked'));
  return ok == true;
}

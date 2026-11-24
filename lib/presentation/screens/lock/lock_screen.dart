import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../providers/providers.dart';

/// Number pad for the app PIN.
class PinPad extends StatelessWidget {
  final int length;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBiometric;
  const PinPad({super.key, required this.value, required this.onChanged, this.length = 4, this.onBiometric});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String k) => SizedBox(
      width: 76,
      height: 64,
      child: TextButton(
        key: Key('pin_$k'),
        onPressed: () => value.length < 8 ? onChanged(value + k) : null,
        child: Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < (value.length > length ? value.length : length); i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.all(7),
                width: 15,
                height: 15,
                decoration: BoxDecoration(shape: BoxShape.circle, color: i < value.length ? cs.primary : cs.outlineVariant),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (final row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(mainAxisSize: MainAxisSize.min, children: [for (final k in row) key(k)]),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 76, height: 64, child: onBiometric == null ? null : IconButton(onPressed: onBiometric, icon: const Icon(Icons.fingerprint_rounded, size: 32))),
                  key('0'),
                  SizedBox(
                    width: 76,
                    height: 64,
                    child: IconButton(onPressed: value.isEmpty ? null : () => onChanged(value.substring(0, value.length - 1)), icon: const Icon(Icons.backspace_outlined)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The app lock (PIN / biometrics).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _msg;
  bool _bio = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = ref.read(settingsProvider);
      final ls = ref.read(lockServiceProvider);
      if (s.biometric && await ls.biometricAvailable()) {
        setState(() => _bio = true);
        _biometric();
      }
    });
  }

  Future<void> _biometric() async {
    if (!mounted) return;
    final ok = await ref.read(lockServiceProvider).authenticate(context.tr('unlock_reason'));
    if (ok) ref.read(lockProvider.notifier).unlock();
  }

  Future<void> _changed(String v) async {
    setState(() => _pin = v);
    if (v.length < ref.read(lockServiceProvider).pinLength) return;
    final ls = ref.read(lockServiceProvider);
    final ok = await ls.checkPin(v);
    if (!mounted) return;
    if (ok) {
      ref.read(lockProvider.notifier).unlock();
    } else {
      final wait = ls.waitSeconds();
      setState(() {
        _pin = '';
        _msg = wait > 0 ? context.tr('pin_wait', {'s': '$wait'}) : context.tr('pin_wrong');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(l.tr('app_name'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(l.tr('enter_pin')),
                const SizedBox(height: 8),
                SizedBox(height: 22, child: _msg == null ? null : Text(_msg!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                PinPad(value: _pin, length: ref.read(lockServiceProvider).pinLength, onChanged: _changed, onBiometric: _bio ? _biometric : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the PIN (or biometrics) once more — the journal lock. Returns true when verified.
Future<bool> verifyIdentity(BuildContext context, WidgetRef ref) async {
  final ls = ref.read(lockServiceProvider);
  final s = ref.read(settingsProvider);
  if (!ls.hasPin) return true;
  if (s.biometric && await ls.biometricAvailable()) {
    if (!context.mounted) return false;
    if (await ls.authenticate(context.tr('unlock_reason'))) return true;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      var pin = '';
      String? msg;
      return StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(ctx.tr('enter_pin')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg != null) Text(msg!, style: const TextStyle(color: Colors.red)),
              PinPad(
                value: pin,
                length: ls.pinLength,
                onChanged: (v) async {
                  setS(() => pin = v);
                  if (v.length < ls.pinLength) return;
                  if (await ls.checkPin(v)) {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    setS(() {
                      pin = '';
                      msg = ctx.tr('pin_wrong');
                    });
                  }
                },
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel')))],
        ),
      );
    },
  );
  return ok == true;
}

/// Sets a new PIN (asked twice). Returns true when saved.
Future<bool> setupPin(BuildContext context, WidgetRef ref) async {
  final ls = ref.read(lockServiceProvider);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      var first = '', pin = '';
      String? msg;
      return StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(ctx.tr(first.isEmpty ? 'choose_pin' : 'confirm_pin')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg != null) Text(msg!, style: const TextStyle(color: Colors.red)),
              PinPad(
                value: pin,
                onChanged: (v) async {
                  setS(() => pin = v);
                  if (v.length < 4) return;
                  if (first.isEmpty) {
                    await Future<void>.delayed(const Duration(milliseconds: 150));
                    setS(() => (first, pin, msg) = (v, '', null));
                  } else if (v == first) {
                    await ls.setPin(v);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    setS(() => (first, pin, msg) = ('', '', ctx.tr('pin_mismatch')));
                  }
                },
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel')))],
        ),
      );
    },
  );
  return ok == true;
}

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/platform_support.dart';

/// App lock: a 4–8 digit PIN (stored only as a salted SHA-256 hash, never the PIN) and, where
/// the device has it, fingerprint / face / Windows Hello. After 5 wrong PINs the lock waits 30 s.
class LockService {
  final SharedPreferences prefs;
  final LocalAuthentication _auth;
  LockService(this.prefs, [LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  static const _kHash = 'lock_pin_hash', _kSalt = 'lock_pin_salt', _kFails = 'lock_fails', _kUntil = 'lock_until';

  bool get hasPin => (prefs.getString(_kHash) ?? '').isNotEmpty;

  /// Digits in the saved PIN (the pad checks once that many are typed).
  int get pinLength => prefs.getInt('lock_pin_len') ?? 4;

  static String hashPin(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool validPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    if (!validPin(pin)) throw ArgumentError('pin');
    final r = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await prefs.setString(_kSalt, salt);
    await prefs.setString(_kHash, hashPin(pin, salt));
    await prefs.setInt('lock_pin_len', pin.length);
    await prefs.remove(_kFails);
    await prefs.remove(_kUntil);
  }

  Future<void> clearPin() async {
    await prefs.remove(_kHash);
    await prefs.remove(_kSalt);
  }

  /// Seconds the user must wait before another attempt (0 = may try now).
  int waitSeconds([DateTime? now]) {
    final until = prefs.getInt(_kUntil) ?? 0;
    final left = until - (now ?? DateTime.now()).millisecondsSinceEpoch;
    return left > 0 ? (left / 1000).ceil() : 0;
  }

  Future<bool> checkPin(String pin, [DateTime? now]) async {
    if (waitSeconds(now) > 0) return false;
    final ok = hashPin(pin, prefs.getString(_kSalt) ?? '') == prefs.getString(_kHash);
    if (ok) {
      await prefs.remove(_kFails);
      return true;
    }
    final fails = (prefs.getInt(_kFails) ?? 0) + 1;
    await prefs.setInt(_kFails, fails);
    if (fails % 5 == 0) await prefs.setInt(_kUntil, (now ?? DateTime.now()).add(const Duration(seconds: 30)).millisecondsSinceEpoch);
    return false;
  }

  Future<bool> biometricAvailable() async {
    if (!PlatformSupport.biometrics) return false;
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

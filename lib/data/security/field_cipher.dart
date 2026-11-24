import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../db/schema.dart';

/// Encrypts the sensitive text columns of the device database (columns marked
/// `secret` in schema.dart) with AES-256-GCM. The 32-byte key lives in the OS
/// keystore (see KeyVault); the database file alone does not reveal them.
///
/// Values are stored as `enc1:` + base64(nonce ‖ ciphertext ‖ tag). Empty strings
/// stay empty. A value without the prefix is read as plain text (older rows).
abstract class FieldCipher {
  String encrypt(String plain);
  String decrypt(String stored);

  static const prefix = 'enc1:';
  static bool isEncrypted(Object? v) => v is String && v.startsWith(prefix);

  /// Encrypts the secret columns of [row] for [table] (a new map; others untouched).
  Map<String, Object?> sealRow(String table, Map<String, Object?> row) {
    final cols = tableDef(table).secretCols;
    if (cols.isEmpty) return row;
    final out = Map<String, Object?>.of(row);
    for (final c in cols) {
      final v = out[c];
      if (v is String && v.isNotEmpty && !isEncrypted(v)) out[c] = encrypt(v);
    }
    return out;
  }

  /// Decrypts the secret columns of [row] for [table] (a new map).
  Map<String, Object?> openRow(String table, Map<String, Object?> row) {
    final cols = tableDef(table).secretCols;
    if (cols.isEmpty) return row;
    final out = Map<String, Object?>.of(row);
    for (final c in cols) {
      final v = out[c];
      if (isEncrypted(v)) out[c] = decrypt(v as String);
    }
    return out;
  }
}

class AesGcmFieldCipher extends FieldCipher {
  final Uint8List _key;
  final Random _rnd = Random.secure();
  AesGcmFieldCipher(List<int> key) : _key = Uint8List.fromList(key) {
    if (_key.length != 32) throw ArgumentError('AES-256 needs a 32-byte key');
  }

  /// Text shown for a value that cannot be decrypted (key lost or data corrupted).
  static const unreadable = '🔒';

  static Uint8List newKey() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  GCMBlockCipher _gcm(bool forEncryption, Uint8List nonce) =>
      GCMBlockCipher(AESEngine())..init(forEncryption, AEADParameters(KeyParameter(_key), 128, nonce, Uint8List(0)));

  @override
  String encrypt(String plain) {
    if (plain.isEmpty) return plain;
    final nonce = Uint8List.fromList(List<int>.generate(12, (_) => _rnd.nextInt(256)));
    final ct = _gcm(true, nonce).process(Uint8List.fromList(utf8.encode(plain)));
    return FieldCipher.prefix + base64.encode([...nonce, ...ct]);
  }

  /// Bytes → nonce ‖ ciphertext ‖ tag (files on the device).
  Uint8List encryptBytes(Uint8List plain) {
    final nonce = Uint8List.fromList(List<int>.generate(12, (_) => _rnd.nextInt(256)));
    final ct = _gcm(true, nonce).process(plain);
    return Uint8List.fromList([...nonce, ...ct]);
  }

  Uint8List decryptBytes(Uint8List sealed) {
    if (sealed.length < 28) throw const FormatException('not an encrypted file');
    return _gcm(false, Uint8List.fromList(sealed.sublist(0, 12))).process(Uint8List.fromList(sealed.sublist(12)));
  }

  @override
  String decrypt(String stored) {
    if (!FieldCipher.isEncrypted(stored)) return stored;
    try {
      final raw = base64.decode(stored.substring(FieldCipher.prefix.length));
      final nonce = Uint8List.fromList(raw.sublist(0, 12));
      final pt = _gcm(false, nonce).process(Uint8List.fromList(raw.sublist(12)));
      return utf8.decode(pt);
    } catch (_) {
      return unreadable;
    }
  }
}

/// Password-based encryption for backup files (PBKDF2-HMAC-SHA256 → AES-256-GCM).
class BackupCrypto {
  BackupCrypto._();
  static const magic = 'NPBK1';
  static const iterations = 120000;

  static Uint8List _derive(String password, Uint8List salt) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  static String seal(String json, String password) {
    final r = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
    final c = AesGcmFieldCipher(_derive(password, salt));
    return jsonEncode({'format': magic, 'salt': base64.encode(salt), 'iter': iterations, 'data': c.encrypt(json)});
  }

  /// Returns the plain JSON, or null when the password is wrong / the file is not a sealed backup.
  static String? open(String sealed, String password) {
    try {
      final m = jsonDecode(sealed) as Map<String, dynamic>;
      if (m['format'] != magic) return null;
      final c = AesGcmFieldCipher(_derive(password, base64.decode(m['salt'] as String)));
      final out = c.decrypt(m['data'] as String);
      return out == AesGcmFieldCipher.unreadable ? null : out;
    } catch (_) {
      return null;
    }
  }
}

/// The private-notes vault: a passphrase only the user knows → AES-256-GCM key (PBKDF2-HMAC-SHA256).
/// Private notes are encrypted ON THE DEVICE before they are saved or synced, so the server
/// (and anyone with database access) only ever sees ciphertext. The salt and a check value
/// (the encryption of a known phrase) sync with the profile so every device can unlock
/// with the same passphrase. A forgotten passphrase cannot be recovered.
class NoteVault {
  static const iterations = 150000;
  static const _probe = 'notes-pro-vault-ok';

  static Uint8List deriveKey(String passphrase, Uint8List salt) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// A new vault: (salt base64, check value, cipher).
  static (String, String, AesGcmFieldCipher) create(String passphrase) {
    final r = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
    final c = AesGcmFieldCipher(deriveKey(passphrase, salt));
    return (base64.encode(salt), c.encrypt(_probe), c);
  }

  /// The cipher for [passphrase], or null when it is wrong.
  static AesGcmFieldCipher? unlock(String passphrase, String saltB64, String check) {
    try {
      final c = AesGcmFieldCipher(deriveKey(passphrase, base64.decode(saltB64)));
      return c.decrypt(check) == _probe ? c : null;
    } catch (_) {
      return null;
    }
  }
}

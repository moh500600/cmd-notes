import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'field_cipher.dart';

/// Where the database key is kept, reported honestly in Settings → Privacy.
enum KeyLocation { secureStorage, appFile, memory }

/// Loads (or creates) the 32-byte key for [AesGcmFieldCipher].
///
/// * Android Keystore / iOS Keychain / Windows Credential Manager via flutter_secure_storage.
/// * If the OS keystore is unavailable, a key file in the app's private folder is used
///   instead (weaker: anyone who can read the app folder can read it) and Settings says so.
class KeyVault {
  static const _name = 'notes_pro_db_key_v1';
  final FlutterSecureStorage _secure;
  KeyVault([FlutterSecureStorage? s]) : _secure = s ?? const FlutterSecureStorage();

  KeyLocation location = KeyLocation.memory;

  Future<List<int>> load(String appDir) async {
    try {
      final v = await _secure.read(key: _name);
      if (v != null) {
        location = KeyLocation.secureStorage;
        return base64.decode(v);
      }
      final file = File('$appDir/.dbkey');
      final k = file.existsSync() ? base64.decode(file.readAsStringSync().trim()) : AesGcmFieldCipher.newKey();
      await _secure.write(key: _name, value: base64.encode(k));
      if (await _secure.read(key: _name) == base64.encode(k)) {
        if (file.existsSync()) file.deleteSync(); // moved into the keystore
        location = KeyLocation.secureStorage;
        return k;
      }
      throw StateError('keystore did not keep the key');
    } catch (_) {
      final file = File('$appDir/.dbkey');
      if (file.existsSync()) {
        location = KeyLocation.appFile;
        return base64.decode(file.readAsStringSync().trim());
      }
      final k = AesGcmFieldCipher.newKey();
      file.writeAsStringSync(base64.encode(k), flush: true);
      location = KeyLocation.appFile;
      return k;
    }
  }
}

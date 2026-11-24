import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/platform/database_bootstrap.dart';
import 'data/db/app_database.dart';
import 'data/db/search_index.dart';
import 'data/security/field_cipher.dart';
import 'data/security/key_vault.dart';
import 'data/services/file_service.dart';
import 'presentation/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  final prefs = await SharedPreferences.getInstance();
  final loc = await resolveDatabase('notes_pro.db');
  final db = await AppDatabase.open(loc.factory, loc.path);
  final index = SearchIndex(db);
  await index.init();
  // The key for encrypted files and the journal: OS keystore (Keychain / Keystore / Credential Manager).
  final vault = KeyVault();
  final key = await vault.load((await getApplicationSupportDirectory()).path);
  await FileService.clearTemp(); // plain copies from opening files last time
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        prefsProvider.overrideWithValue(prefs),
        searchIndexProvider.overrideWithValue(index),
        cipherProvider.overrideWithValue(AesGcmFieldCipher(key)),
        keyLocationProvider.overrideWithValue(vault.location),
      ],
      child: const NotesProApp(),
    ),
  );
}

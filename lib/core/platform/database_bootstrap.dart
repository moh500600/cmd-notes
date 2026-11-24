import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'platform_support.dart';

/// Where and how the app's SQLite database is opened.
class DatabaseLocation {
  final DatabaseFactory factory;
  final String path;
  const DatabaseLocation(this.factory, this.path);
}

/// Android/iOS: the default databases folder, opened through the bundled SQLite (FFI)
/// when it loads, else the platform sqflite plugin.
///
/// Windows/Linux/macOS: sqflite_common_ffi (SQLite through dart:ffi, bundled
/// with the app) and a per-user folder:
///   Windows  `%APPDATA%\<company>\<product>\databases`
///   Linux    `~/.local/share/<application id>/databases`
/// The schema and migrations are the same AppDatabase code on every platform.
Future<DatabaseLocation> resolveDatabase(String fileName) async {
  if (PlatformSupport.isDesktop) {
    sqfliteFfiInit();
    // Anything that still asks sqflite for its default factory gets FFI too.
    mobile.databaseFactory = databaseFactoryFfi;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'databases'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return DatabaseLocation(databaseFactoryFfi, p.join(dir.path, fileName));
  }
  final path = p.join(await mobile.getDatabasesPath(), fileName);
  // Android/iOS: prefer the SQLite bundled with the app (through dart:ffi) — it has FTS5 for
  // full-text search on every phone. If it cannot load, fall back to the system SQLite
  // (search then uses FTS4 or a plain scan; nothing else changes).
  try {
    sqfliteFfiInit();
    final probe = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await probe.close();
    return DatabaseLocation(databaseFactoryFfi, path);
  } catch (_) {
    return DatabaseLocation(mobile.databaseFactory, path);
  }
}

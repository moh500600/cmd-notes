import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _ns = '2b7e5c90-4f1a-4d36-8e2b-6a9d0c3f1e57'; // CMD Notes namespace for stable ids

/// A new random UUID (v4) — the row id on the device and on the server.
String newId() => _uuid.v4();

/// A stable UUID (v5) for a natural key, so the same fact recorded on two devices
/// (one dose at one time, steps of one day, a habit on one day) is ONE row and the
/// last write wins instead of creating duplicates.
String stableId(String key) => _uuid.v5(_ns, key);

/// Whether [s] looks like a UUID (server columns are typed uuid).
bool isUuid(String? s) => s != null && RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(s);

/// Open editors register a flush callback here; the app calls [flushAll] when it is paused,
/// hidden or about to be closed, so typed text reaches the database before the OS can kill it.
class AutosaveBus {
  AutosaveBus._();
  static final _flushers = <Object, Future<void> Function()>{};

  static void register(Object owner, Future<void> Function() flush) => _flushers[owner] = flush;
  static void unregister(Object owner) => _flushers.remove(owner);

  static Future<void> flushAll() async {
    for (final f in List.of(_flushers.values)) {
      try {
        await f();
      } catch (_) {}
    }
  }
}

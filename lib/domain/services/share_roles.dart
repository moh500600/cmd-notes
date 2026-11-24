/// Sharing roles (enforced by the server's RLS; the app mirrors them to show the right buttons).
enum ShareRole { view, comment, edit }

ShareRole roleOf(String? s) => switch (s) {
  'edit' => ShareRole.edit,
  'comment' => ShareRole.comment,
  _ => ShareRole.view,
};

extension ShareRoleX on ShareRole {
  bool get canRead => true;
  bool get canComment => this == ShareRole.comment || this == ShareRole.edit;
  bool get canEdit => this == ShareRole.edit;
  // Only the owner pins, trashes, moves, deletes, re-shares or encrypts a note.
  bool get canManage => false;
}

/// The strongest role among several shares (a note shared directly AND through its notebook).
ShareRole strongest(Iterable<ShareRole> roles) {
  var r = ShareRole.view;
  for (final x in roles) {
    if (x.index > r.index) r = x;
  }
  return r;
}

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
String? normalizeShareEmail(String s) {
  final e = s.trim().toLowerCase();
  return _email.hasMatch(e) ? e : null;
}

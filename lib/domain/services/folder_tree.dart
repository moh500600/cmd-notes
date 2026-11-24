import '../entities/entities.dart';

/// Notebooks form a tree: a root is a notebook, a child is a folder (any depth).
class FolderNode {
  final Notebook notebook;
  final List<FolderNode> children;
  final int depth;
  FolderNode(this.notebook, this.children, this.depth);
}

class FolderTree {
  final List<Notebook> all;
  late final Map<String, Notebook> byId = {for (final n in all) n.id: n};
  late final Map<String?, List<Notebook>> _kids = () {
    final m = <String?, List<Notebook>>{};
    for (final n in all) {
      // a parent that no longer exists (deleted on another device) makes the folder a root
      final p = n.parentId != null && byId.containsKey(n.parentId) ? n.parentId : null;
      (m[p] ??= []).add(n);
    }
    for (final l in m.values) {
      l.sort(compare);
    }
    return m;
  }();

  FolderTree(this.all);

  /// Pinned first, then the user's order, then name.
  static int compare(Notebook a, Notebook b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final o = a.sortOrder.compareTo(b.sortOrder);
    return o != 0 ? o : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  List<Notebook> childrenOf(String? id) => _kids[id] ?? const [];
  List<Notebook> get roots => childrenOf(null);

  List<FolderNode> build() {
    List<FolderNode> rec(String? parent, int depth, Set<String> seen) => [
      for (final n in childrenOf(parent))
        if (seen.add(n.id)) FolderNode(n, rec(n.id, depth + 1, seen), depth),
    ];
    return rec(null, 0, <String>{});
  }

  /// Depth-first list (for pickers), each with its depth.
  List<(Notebook, int)> flat() {
    final out = <(Notebook, int)>[];
    void walk(List<FolderNode> ns) {
      for (final n in ns) {
        out.add((n.notebook, n.depth));
        walk(n.children);
      }
    }

    walk(build());
    return out;
  }

  /// [id] and every folder below it.
  Set<String> descendantsOf(String id) {
    final out = <String>{id};
    final stack = [id];
    while (stack.isNotEmpty) {
      for (final c in childrenOf(stack.removeLast())) {
        if (out.add(c.id)) stack.add(c.id);
      }
    }
    return out;
  }

  /// Whether [id] may move under [newParent] (not into itself or its own sub-folder).
  bool canMove(String id, String? newParent) => newParent == null || !descendantsOf(id).contains(newParent);

  /// "Work › Projects › 2026"
  String path(String? id, {String sep = ' › '}) {
    final names = <String>[];
    final seen = <String>{};
    var cur = id == null ? null : byId[id];
    while (cur != null && seen.add(cur.id)) {
      names.insert(0, cur.name);
      cur = cur.parentId == null ? null : byId[cur.parentId];
    }
    return names.join(sep);
  }

  /// Sort orders 0..n for [ordered] siblings (after a drag/drop or up/down move).
  static Map<String, int> reorder(List<Notebook> ordered) => {for (var i = 0; i < ordered.length; i++) ordered[i].id: i};
}

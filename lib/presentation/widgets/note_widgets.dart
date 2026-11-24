import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/text_tools.dart';
import '../../domain/entities/entities.dart';
import '../../domain/services/notes_data.dart';

IconData typeIcon(String t) => switch (t) {
  'study' => Icons.school_rounded,
  'work' => Icons.work_rounded,
  'meeting' => Icons.groups_rounded,
  'personal' => Icons.person_rounded,
  'journal' => Icons.auto_stories_rounded,
  'idea' => Icons.lightbulb_rounded,
  'shopping' => Icons.shopping_cart_rounded,
  'todo' => Icons.checklist_rounded,
  'code' => Icons.code_rounded,
  'voice' => Icons.mic_rounded,
  _ => Icons.notes_rounded,
};

/// Icons a notebook / template can have (stored by name).
const kNotebookIcons = <String, IconData>{
  'book': Icons.menu_book_rounded,
  'folder': Icons.folder_rounded,
  'work': Icons.work_rounded,
  'school': Icons.school_rounded,
  'home': Icons.home_rounded,
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
  'idea': Icons.lightbulb_rounded,
  'code': Icons.code_rounded,
  'travel': Icons.flight_rounded,
  'money': Icons.payments_rounded,
  'health': Icons.favorite_border_rounded,
  'music': Icons.music_note_rounded,
  'camera': Icons.photo_camera_rounded,
  'cart': Icons.shopping_cart_rounded,
  'people': Icons.groups_rounded,
  'science': Icons.science_rounded,
  'archive': Icons.inventory_2_rounded,
};

const kTemplateIcons = <String, IconData>{
  'groups': Icons.groups_rounded,
  'school': Icons.school_rounded,
  'rocket_launch': Icons.rocket_launch_rounded,
  'today': Icons.today_rounded,
  'date_range': Icons.date_range_rounded,
  'calendar_month': Icons.calendar_month_rounded,
  'auto_stories': Icons.auto_stories_rounded,
  'science': Icons.science_rounded,
  'checklist': Icons.checklist_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'flag': Icons.flag_rounded,
  'description': Icons.description_rounded,
};

IconData notebookIcon(String name) => kNotebookIcons[name] ?? Icons.menu_book_rounded;
IconData templateIcon(String name) => kTemplateIcons[name] ?? kNotebookIcons[name] ?? Icons.description_rounded;

String typeLabel(L10n l, String t) => l.tr('type_$t');

/// Direction of user text: Arabic text right-to-left, English left-to-right, whatever the UI language.
TextDirection dirOf(String text, BuildContext context) {
  final t = text.trim();
  if (t.isEmpty) return Directionality.of(context);
  for (final r in t.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFC)) return TextDirection.rtl;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) return TextDirection.ltr;
  }
  return Directionality.of(context);
}

/// A note in a list or grid.
class NoteCard extends StatelessWidget {
  final Note note;
  final NotesData data;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool compact;
  const NoteCard({super.key, required this.note, required this.data, required this.onTap, this.onLongPress, this.trailing, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cs = Theme.of(context).colorScheme;
    final color = note.color.isNotEmpty ? AppColors.parse(note.color) : AppColors.type(note.type);
    final tags = data.tagsOf(note.id);
    final nb = note.notebookId == null ? null : data.tree.byId[note.notebookId];
    final (done, total) = note.isPrivate ? (0, 0) : note.doc.checklist;
    final body = note.isPrivate ? l.tr('private_note_hidden') : preview(note.plainText, compact ? 90 : 160);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: color, width: 4))),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(typeIcon(note.type), size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note.displayTitle(l.tr('untitled')),
                      textDirection: dirOf(note.displayTitle(l.tr('untitled')), context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                  ),
                  if (note.isPrivate) Icon(Icons.lock_rounded, size: 16, color: cs.onSurfaceVariant),
                  if (note.pinned) const Icon(Icons.push_pin_rounded, size: 16, color: AppColors.amber),
                  if (note.favorite) const Icon(Icons.star_rounded, size: 17, color: AppColors.warning),
                  ?trailing,
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  body,
                  textDirection: dirOf(body, context),
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5, height: 1.35, fontStyle: note.isPrivate ? FontStyle.italic : null),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l.dateShort(note.updatedAt), style: TextStyle(fontSize: 11.5, color: cs.outline)),
                  if (nb != null) _Chip(icon: notebookIcon(nb.icon), text: nb.name, color: AppColors.parse(nb.color)),
                  if (total > 0) _Chip(icon: Icons.check_box_rounded, text: '$done/$total', color: AppColors.success),
                  if (note.remindAt != null || note.reviewAt != null || note.eventAt != null) _Chip(icon: Icons.alarm_rounded, text: l.dateShort((note.eventAt ?? note.remindAt ?? note.reviewAt)!), color: AppColors.info),
                  for (final t in tags.take(3)) _Chip(icon: Icons.tag_rounded, text: t.name, color: AppColors.parse(t.color)),
                  if (tags.length > 3) Text('+${tags.length - 3}', style: TextStyle(fontSize: 11, color: cs.outline)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Chip({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// Colour swatches.
class ColorPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowNone;
  const ColorPicker({super.key, required this.value, required this.onChanged, this.allowNone = false});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (allowNone)
        _swatch(context, '', Theme.of(context).colorScheme.surfaceContainer, child: const Icon(Icons.format_color_reset_rounded, size: 18)),
      for (final c in AppColors.swatches) _swatch(context, c, AppColors.parse(c)),
    ],
  );

  Widget _swatch(BuildContext context, String hex, Color c, {Widget? child}) {
    final sel = value.toUpperCase() == hex.toUpperCase();
    return InkWell(
      key: Key('color_$hex'),
      borderRadius: BorderRadius.circular(20),
      onTap: () => onChanged(hex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: sel ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 2.5),
        ),
        child: sel && child == null ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : child,
      ),
    );
  }
}

class IconPicker extends StatelessWidget {
  final String value;
  final Map<String, IconData> icons;
  final ValueChanged<String> onChanged;
  final Color color;
  const IconPicker({super.key, required this.value, required this.onChanged, required this.color, this.icons = kNotebookIcons});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final e in icons.entries)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: e.key == value ? color.withValues(alpha: 0.2) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: Icon(e.value, color: e.key == value ? color : Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
    ],
  );
}

/// Picks a notebook / folder (or "none"). Returns '' for none, null when cancelled.
Future<String?> pickNotebook(BuildContext context, NotesData d, {String? current, String? excludeTree, bool allowNone = true}) {
  final l = context.l;
  final excluded = excludeTree == null ? const <String>{} : d.tree.descendantsOf(excludeTree);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(l.tr('choose_notebook'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            if (allowNone)
              ListTile(
                leading: const Icon(Icons.inbox_rounded),
                title: Text(l.tr('no_notebook')),
                trailing: current == null ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
            for (final (nb, depth) in d.tree.flat())
              if (!excluded.contains(nb.id))
                ListTile(
                  contentPadding: EdgeInsetsDirectional.only(start: 16.0 + depth * 22, end: 16),
                  leading: Icon(depth == 0 ? notebookIcon(nb.icon) : Icons.folder_rounded, color: AppColors.parse(nb.color)),
                  title: Text(nb.name),
                  trailing: current == nb.id ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(ctx, nb.id),
                ),
          ],
        ),
      ),
    ),
  );
}

/// Text prompt dialog.
Future<String?> promptText(BuildContext context, String title, {String initial = '', String? hint, int maxLines = 1, TextDirection? dir}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: maxLines,
        textDirection: dir,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(context.tr('ok'))),
      ],
    ),
  );
}

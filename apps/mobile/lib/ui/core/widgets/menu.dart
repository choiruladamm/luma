import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';
import 'buttons.dart';

class AppMenuItem<T> {
  const AppMenuItem(
    this.value,
    this.label, {
    this.icon,
    this.destructive = false,
    this.selected = false,
  });

  final T value;
  final String label;
  final List<List<dynamic>>? icon;
  final bool destructive;

  /// Opsi yang lagi aktif di menu pilihan (dapet centang).
  final bool selected;
}

/// Menu pilihan yang nempel ke widget [context], mis. "Urutin pake" (board
/// Komponen 04, baris 46, centang di yang [AppMenuItem.selected]). Menu tekan
/// lama buku ada di `book_menu.dart`.
Future<T?> showAppMenu<T>(
  BuildContext context,
  List<AppMenuItem<T>> items, {
  required String title,
}) {
  final c = context.stabilo;
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    items: [
      PopupMenuItem<T>(
        enabled: false,
        height: 0,
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 6),
        child: Text(
          title,
          style: StabiloType.tag.copyWith(color: c.ink2, height: 1.2),
        ),
      ),
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          child: IconTheme.merge(
            data: IconThemeData(color: item.destructive ? c.danger : c.ink),
            child: Row(
              spacing: Space.s3,
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    style: StabiloType.label.copyWith(
                      color: item.destructive ? c.danger : c.ink,
                      fontWeight: item.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (item.selected)
                  const AppIcon(AppIcons.check)
                else if (item.icon != null)
                  AppIcon(item.icon!),
              ],
            ),
          ),
        ),
    ],
  );
}

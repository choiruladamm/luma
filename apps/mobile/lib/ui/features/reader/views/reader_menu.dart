import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import 'reader_capsule.dart';

enum ReaderMenuAction { search, results, display }

/// Menu ⋯ di kapsul atas: Cari kata, Atur tampilan. Popover kapsul-style
/// (garis 1,5, radius 20, baris 50), rata kanan, 10pt di bawah kapsul. Null
/// kalau ditutup tanpa milih. Lagi mode cari ([resultsFor] = kata yang dicari)
/// item pertamanya jadi "Lihat hasil “kata”" (balik ke daftar hasil).
Future<ReaderMenuAction?> showReaderMenu(
  BuildContext context, {
  String? resultsFor,
}) {
  final c = context.stabilo;
  final size = MediaQuery.sizeOf(context);
  final top =
      MediaQuery.paddingOf(context).top +
      capsuleTopGap +
      capsuleHeight +
      Space.s2 +
      2;
  return showMenu<ReaderMenuAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      size.width - Layout.margin - Layout.readerMenuWidth,
      top,
      Layout.margin,
      size.height - top,
    ),
    color: c.sheet,
    elevation: 6,
    shadowColor: c.ink.withValues(alpha: 0.10),
    menuPadding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: Layout.readerMenuWidth),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
      side: BorderSide(color: c.capsuleLine, width: Layout.outline),
    ),
    clipBehavior: Clip.antiAlias,
    items: [
      _item(
        context,
        resultsFor == null ? ReaderMenuAction.search : ReaderMenuAction.results,
        resultsFor == null ? 'Cari kata' : 'Lihat hasil “$resultsFor”',
        icon: const AppIcon(AppIcons.search, size: 19),
        last: false,
      ),
      _item(
        context,
        ReaderMenuAction.display,
        'Atur tampilan',
        subtitle: 'Ukuran, font, tema',
        icon: Text(
          'Aa',
          style: StabiloType.label.copyWith(fontSize: 16, color: c.ink),
        ),
        last: true,
      ),
    ],
  );
}

PopupMenuItem<ReaderMenuAction> _item(
  BuildContext context,
  ReaderMenuAction value,
  String title, {
  required Widget icon,
  String? subtitle,
  required bool last,
}) {
  final c = context.stabilo;
  return PopupMenuItem<ReaderMenuAction>(
    value: value,
    height: Layout.readerMenuRow,
    padding: EdgeInsets.zero,
    child: Container(
      constraints: const BoxConstraints(minHeight: Layout.readerMenuRow),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.menuLine)),
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          SizedBox(width: 22, child: Center(child: icon)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Text(
                  title,
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: StabiloType.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.ink2,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

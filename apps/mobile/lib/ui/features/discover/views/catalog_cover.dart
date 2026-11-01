import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../domain/catalog/catalog_row.dart';
import '../../../../domain/models/catalog.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/book_cover.dart';

/// Cover dari jaringan (`cached_network_image`, docs/discover.md). Belum
/// kemuat = kotak muted; gagal / gak ada URL = cover default dari judul.
class CatalogCover extends StatelessWidget {
  const CatalogCover({super.key, required this.book, required this.width});

  final CatalogBook book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final height = width / Layout.coverAspect;
    final radius = BorderRadius.circular(BookCover.radiusFor(width));
    final fallback = BookCover(
      title: book.title,
      author: book.authorsLabel,
      width: width,
    );
    if (book.coverUrl.isEmpty) return fallback;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: radius,
        border: Border.all(color: c.outline, width: Layout.outline),
      ),
    );
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: book.coverUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => fallback,
        imageBuilder: (_, image) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: c.outline, width: Layout.outline),
            image: DecorationImage(image: image, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

extension CatalogBookLabels on CatalogBook {
  /// "Jane Austen" dari "Austen, Jane"; beberapa penulis dipisah " · ".
  String? get authorsLabel =>
      authors.isEmpty ? null : authors.map((a) => a.displayName).join(' · ');
}

extension CatalogAuthorLabels on CatalogAuthor {
  /// "Austen, Jane" → "Jane Austen". Nama tanpa koma dibiarin.
  String get displayName {
    final i = name.indexOf(', ');
    if (i < 0) return name;
    return '${name.substring(i + 2)} ${name.substring(0, i)}';
  }

  /// "1775–1817", "1900–", "–1468"; null kalau dua-duanya gak ada.
  String? get years =>
      birth == null && death == null ? null : '${birth ?? ''}–${death ?? ''}';
}

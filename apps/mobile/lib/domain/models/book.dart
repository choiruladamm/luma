/// Asal buku. EPUB di MVP; Markdown nanti (docs bagian 13).
enum SourceType { epub, markdown }

/// Jenis blok di chapter. Heading & sceneBreak gak punya grup, gak bisa di-tap.
enum ParagraphType { paragraph, heading, sceneBreak }

/// Satu blok hasil parse chapter, sebelum dikasih grup.
typedef RawParagraph = ({ParagraphType type, String text});

/// Satu buku di rak.
class ShelfBook {
  const ShelfBook({
    required this.id,
    required this.title,
    required this.author,
    required this.coverName,
    required this.opened,
  });

  final int id;
  final String title;
  final String? author;

  /// Nama file cover di `covers/`; null = cover default.
  final String? coverName;

  /// Udah pernah dibuka (stiker "Baru" ilang).
  final bool opened;
}

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
    required this.createdAt,
  });

  final int id;
  final String title;
  final String? author;

  /// Nama file cover di `covers/`; null = cover default.
  final String? coverName;

  /// Udah pernah dibuka (stiker "Baru" ilang).
  final bool opened;

  /// Kapan diimport.
  final DateTime createdAt;
}

class ChapterInfo {
  const ChapterInfo({
    required this.id,
    required this.title,
    required this.charOffset,
    required this.chars,
  });

  final int id;
  final String title;

  /// Karakter sebelum chapter ini & panjang chapter ini, buat persentase.
  final int charOffset;
  final int chars;
}

/// Buku yang lagi dibaca: judul + daftar chapter urut `sortOrder`.
class ReaderBook {
  const ReaderBook({
    required this.id,
    required this.title,
    required this.totalChars,
    required this.chapters,
  });

  final int id;
  final String title;
  final int totalChars;
  final List<ChapterInfo> chapters;
}

class ReaderParagraph {
  const ReaderParagraph({
    required this.index,
    required this.groupIndex,
    required this.type,
    required this.text,
  });

  final int index;

  /// Null buat heading & scene break.
  final int? groupIndex;
  final ParagraphType type;
  final String text;
}

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
    this.progress = 0,
    this.finished = false,
    this.chapter = 1,
    this.chapterCount = 1,
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

  /// Persentase baca 0..1 dari posisi tersimpan (docs bagian 8).
  final double progress;

  /// Posisi tersimpan di ujung paragraf terakhir bab terakhir: layar akhir
  /// buku udah kebuka.
  final bool finished;

  /// Bab posisi tersimpan (urutan 1-based) dari [chapterCount] bab.
  final int chapter, chapterCount;
}

/// Urutan rak (menu "Urutin pake"). Default [lastOpened].
enum ShelfSort {
  lastOpened('Terakhir dibuka'),
  title('Judul (A–Z)'),
  added('Baru ditambah');

  const ShelfSort(this.label);

  final String label;
}

/// Tampilan rak: grid kartu atau daftar baris. Default [grid].
enum ShelfView { grid, list }

/// Isi sheet Info buku yang gak dibawa tiap baris rak.
class BookInfo {
  const BookInfo({
    required this.lastOpenedAt,
    required this.createdAt,
    required this.fileName,
    required this.fileBytes,
    required this.translated,
  });

  final DateTime? lastOpenedAt;
  final DateTime createdAt;
  final String? fileName;

  /// Ukuran EPUB di Documents; null kalau file-nya gak ada.
  final int? fileBytes;

  /// Paragraf yang udah diartiin di seluruh buku.
  final int translated;
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

/// Rekap buat layar akhir buku (board 12 Akhir buku).
class BookEnd {
  const BookEnd({
    required this.author,
    required this.coverName,
    required this.readingSeconds,
    required this.translated,
  });

  final String? author;
  final String? coverName;

  /// Total waktu baca aktif.
  final int readingSeconds;

  /// Paragraf yang udah diartiin di seluruh buku.
  final int translated;
}

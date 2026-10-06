/// Asal buku. EPUB di MVP; Markdown nanti (docs bagian 13).
enum SourceType { epub, markdown }

/// Jenis blok di chapter. Heading & sceneBreak gak punya grup, gak bisa di-tap.
enum ParagraphType { paragraph, heading, sceneBreak }

/// Satu blok hasil parse chapter, sebelum dikasih grup.
typedef RawParagraph = ({ParagraphType type, String text});

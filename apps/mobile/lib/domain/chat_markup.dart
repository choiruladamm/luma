/// Potongan teks jawaban dengan gaya inline-nya.
class ChatSpan {
  const ChatSpan(this.text, {this.bold = false, this.italic = false});
  final String text;
  final bool bold, italic;

  @override
  bool operator ==(Object other) =>
      other is ChatSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() => 'ChatSpan(${bold ? '**' : ''}${italic ? '*' : ''}$text)';
}

/// Markup inline jawaban Ngobrolin buku: cuma `**tebal**` dan `*miring*`.
/// Toleran buat teks yang lagi di-stream: penanda yang belum ketutup gak pernah
/// tampil sebagai tanda bintang, teks sesudahnya langsung bergaya. Markdown lain
/// (heading, link, kode, tanda daftar di awal) dibuang jadi teks polos.
List<ChatSpan> parseChatMarkup(String raw) {
  final text = _plain(raw);
  final spans = <ChatSpan>[];
  final buffer = StringBuffer();
  var bold = false, italic = false;

  void flush() {
    if (buffer.isEmpty) return;
    final last = spans.isEmpty ? null : spans.last;
    final chunk = buffer.toString();
    buffer.clear();
    if (last != null && last.bold == bold && last.italic == italic) {
      spans[spans.length - 1] = ChatSpan(
        last.text + chunk,
        bold: bold,
        italic: italic,
      );
    } else {
      spans.add(ChatSpan(chunk, bold: bold, italic: italic));
    }
  }

  bool space(int i) =>
      i < 0 || i >= text.length ? false : text[i].trim().isEmpty;

  var i = 0;
  while (i < text.length) {
    if (text[i] != '*') {
      buffer.write(text[i++]);
      continue;
    }
    var run = 0;
    while (i + run < text.length && text[i + run] == '*') {
      run++;
    }
    final end = i + run;
    // Pembuka: sesudahnya bukan spasi (atau ujung teks yang lagi ditulis).
    // Penutup: sebelumnya bukan spasi.
    final canOpen = !space(end);
    final canClose = i > 0 && !space(i - 1);
    final toggleBold = run >= 2;
    final toggleItalic = run == 1 || run >= 3;
    final isOpen = (toggleBold ? bold : false) || (toggleItalic && italic);
    final acts = isOpen ? canClose : canOpen;
    if (!acts) {
      buffer.write('*' * run);
      i = end;
      continue;
    }
    flush();
    if (toggleBold) bold = !bold;
    if (toggleItalic) italic = !italic;
    // Sisa bintang di luar pola 1/2/3 (mis. 4+) dibuang.
    i = end;
  }
  flush();
  return spans;
}

/// Teks tanpa penanda, buat hitung huruf dan semantik.
String chatPlainText(String raw) =>
    parseChatMarkup(raw).map((s) => s.text).join();

final _fence = RegExp(r'```[^\n]*\n?|`');
final _link = RegExp(r'\[([^\]\n]+)\]\([^)\n]*\)');
final _heading = RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true);
final _marker = RegExp(r'^[ \t]*(?:[-•]|\d+[.)])[ \t]+');

String _plain(String raw) {
  final text = raw
      .replaceAll(_fence, '')
      .replaceAllMapped(_link, (m) => m[1]!)
      .replaceAll(_heading, '');
  // Tanda daftar di awal teks: aplikasi yang nomorin, bukan model.
  return text.replaceFirst(_marker, '');
}

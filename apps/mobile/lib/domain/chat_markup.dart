import 'models/book_chat.dart';

/// A piece of answer text with its inline style.
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

/// Inline markup of a Ngobrolin buku answer: only `**bold**` and `*italic*`.
/// Tolerant of streamed text: an unclosed marker never shows as an asterisk, and
/// the text after it is styled right away. Other markdown (headings, links, code,
/// leading list markers) is stripped to plain text.
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
    // Opener: not followed by a space (or the end of the text being written).
    // Closer: not preceded by a space.
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
    // Leftover asterisks beyond the 1/2/3 patterns (e.g. 4+) are dropped.
    i = end;
  }
  flush();
  return spans;
}

/// Text without markers, for counting letters and semantics.
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
  // Leading list marker: the app numbers items, not the model.
  return text.replaceFirst(_marker, '');
}

/// Layout used for display, after cleaning up the model's wrong labels. The
/// stored answer data is unchanged.
/// - An intro sentence before a list that ends with ":" is not an item.
/// - If the first item doesn't start with **bold** while every later item does
///   (a prompt rule), it is an intro, not an item.
/// - A list with a single item is not a list.
/// - [streaming]: the last block whose first line is a list item may not be an
///   item yet (it could be an intro still being written), so show a paragraph first.
/// All of these fall back to a paragraph.
List<ChatAnswerLayout> chatDisplayLayouts(
  List<ChatAnswerBlock> blocks, {
  bool streaming = false,
}) {
  bool listy(ChatAnswerLayout l) =>
      l == ChatAnswerLayout.item || l == ChatAnswerLayout.bullet;
  bool bold(String text) {
    final spans = parseChatMarkup(text);
    return spans.isNotEmpty && spans.first.bold;
  }

  final layouts = [
    for (final b in blocks)
      listy(b.layout) && chatPlainText(b.text).trimRight().endsWith(':')
          ? ChatAnswerLayout.paragraph
          : b.layout,
  ];
  var start = 0;
  while (start < layouts.length) {
    var end = start + 1;
    if (listy(layouts[start])) {
      while (end < layouts.length && layouts[end] == layouts[start]) {
        end++;
      }
      if (end - start >= 2 &&
          !bold(blocks[start].text) &&
          [for (var i = start + 1; i < end; i++) i]
              .every((i) => bold(blocks[i].text))) {
        layouts[start] = ChatAnswerLayout.paragraph;
        start++;
      }
      if (end - start < 2) {
        for (var i = start; i < end; i++) {
          layouts[i] = ChatAnswerLayout.paragraph;
        }
      }
    }
    start = end;
  }
  if (streaming) {
    final last = blocks.lastIndexWhere((b) => b.text.isNotEmpty);
    if (last >= 0 &&
        listy(layouts[last]) &&
        (last == 0 || layouts[last - 1] != layouts[last])) {
      layouts[last] = ChatAnswerLayout.paragraph;
    }
  }
  return layouts;
}

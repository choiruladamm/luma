import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/chat_markup.dart';

void main() {
  List<ChatSpan> parse(String s) => parseChatMarkup(s);

  test('plain text is a single span', () {
    expect(parse('Halo dunia.'), [const ChatSpan('Halo dunia.')]);
    expect(parse(''), isEmpty);
  });

  test('bold and italic', () {
    expect(parse('Ini **penting** banget'), [
      const ChatSpan('Ini '),
      const ChatSpan('penting', bold: true),
      const ChatSpan(' banget'),
    ]);
    expect(parse('Judul *Meditations* ya'), [
      const ChatSpan('Judul '),
      const ChatSpan('Meditations', italic: true),
      const ChatSpan(' ya'),
    ]);
    expect(parse('***kuat***'), [
      const ChatSpan('kuat', bold: true, italic: true),
    ]);
  });

  test('bold can contain italic', () {
    expect(parse('**a *b* c**'), [
      const ChatSpan('a ', bold: true),
      const ChatSpan('b', bold: true, italic: true),
      const ChatSpan(' c', bold: true),
    ]);
  });

  test('unclosed markers never show asterisks while streaming', () {
    expect(parse('Ini **pent'), [
      const ChatSpan('Ini '),
      const ChatSpan('pent', bold: true),
    ]);
    expect(parse('Ini **'), [const ChatSpan('Ini ')]);
    expect(parse('Ini *'), [const ChatSpan('Ini ')]);
  });

  test('stray asterisks around spaces stay literal', () {
    expect(chatPlainText('2 * 3 = 6'), '2 * 3 = 6');
    expect(chatPlainText('bintang * sendirian'), 'bintang * sendirian');
  });

  test('other markdown is dropped to plain text', () {
    expect(chatPlainText('## Judul\nIsi'), 'Judul\nIsi');
    expect(chatPlainText('Lihat [ini](http://x.y) dong'), 'Lihat ini dong');
    expect(chatPlainText('pakai `kode` aja'), 'pakai kode aja');
    expect(chatPlainText('- butir'), 'butir');
    expect(chatPlainText('1. butir'), 'butir');
    expect(chatPlainText('snake_case_name'), 'snake_case_name');
  });

  test('plain text is the same however far the stream got', () {
    const full = '**Siapin mental.** Tiap pagi dia ngingetin *diri*.';
    final plain = chatPlainText(full);
    for (var n = 0; n <= full.length; n++) {
      final partial = chatPlainText(full.substring(0, n));
      expect(plain.startsWith(partial), isTrue, reason: 'n=$n "$partial"');
    }
  });
}

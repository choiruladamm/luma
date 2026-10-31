import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/chat_preview.dart';
import 'package:luma/domain/models/book_chat.dart';

void main() {
  final source = ChatSource(
    id: 'S1',
    chapterTitle: 'Bab',
    anchors: [
      SourceAnchor(
        book: (bookId: 1, contentRevision: 1),
        chapterId: 1,
        paragraphIndex: 0,
        start: 0,
        end: 5,
        paragraphHash: 'hash',
        snapshot: 'Bukti',
      ),
    ],
  );
  // Use JSON encoding for ordinary escapes, then exercise escaped surrogate pairs separately.
  final wire = jsonEncode({
    'status': 'answered',
    'parts': [
      {
        'text': 'Halo "kutip" \\ \n 😀',
        'kind': 'book',
        'source_ids': ['S1'],
      },
      {'text': 'Lanjut', 'kind': 'external', 'source_ids': []},
    ],
  }).replaceAll('😀', r'\uD83D\uDE00');

  test(
    'every split preserves escaped text and cites only complete objects',
    () {
      for (var cut = 0; cut <= wire.length; cut++) {
        final reader = ChatPreviewDecoder(sources: [source]);
        reader.add(wire.substring(0, cut));
        expect(reader.invalid, false, reason: 'cut $cut');
        if (cut < wire.indexOf('},{') + 1) {
          expect(reader.blocks.every((b) => b.sources.isEmpty), true);
        }
        reader.add(wire.substring(cut));
        expect(reader.invalid, false, reason: 'cut $cut');
        expect(reader.blocks.map((b) => b.text), [
          'Halo "kutip" \\ \n 😀',
          'Lanjut',
        ]);
        expect(reader.blocks.first.sources, [source]);
        expect(reader.blocks.last.sources, isEmpty);
      }
    },
  );

  test(
    'single UTF16 units delay incomplete Unicode and expose pre-DONE text',
    () {
      final reader = ChatPreviewDecoder(sources: [source]);
      final direct = wire.replaceAll(r'\uD83D\uDE00', '😀');
      for (final unit in direct.codeUnits) {
        reader.add(String.fromCharCode(unit));
        for (final b in reader.blocks) {
          expect(chatValidUnicode(b.text), true);
        }
      }
      expect(reader.invalid, false);
      final partial = ChatPreviewDecoder()..add('{"parts":[{"text":"Hai');
      expect(partial.blocks.single.text, 'Hai');
      expect(partial.blocks.single.sources, isEmpty);
      partial.add(r'\uD83D');
      expect(partial.blocks.single.text, 'Hai');
      partial.add(r'\uDE00');
      expect(partial.blocks.single.text, 'Hai😀');
    },
  );

  test('only direct parts text, no nested aliases or other fields', () {
    final reader = ChatPreviewDecoder()
      ..add(
        '{"text":"hidden","other":{"parts":[{"text":"hidden"}]},"parts":[{"nested":{"text":"hidden"},"text":"Shown","kind":"conversation","source_ids":[]}]}',
      );
    expect(reader.invalid, false);
    expect(reader.blocks.single.text, 'Shown');
    expect(chatDraftPreview(wire).map((b) => b.text).length, 2);
    expect(chatDraftPreview(wire).every((b) => b.sources.isEmpty), true);
    expect(chatDraftPreview('{"claims":[{"text":"legacy"}]}'), isEmpty);
  });

  test('malformed suffix, duplicate escaped keys, wrong kind/source revoke all citations', () {
    for (final suffix in [
      ',"status":"partial"}',
      r',"\u0070arts":[]}',
      'junk',
    ]) {
      final reader = ChatPreviewDecoder(sources: [source])..add(wire);
      expect(reader.blocks.first.sources, isNotEmpty);
      reader.add(suffix);
      expect(reader.invalid, true);
      expect(reader.blocks.every((b) => b.sources.isEmpty), true);
      expect(reader.blocks.first.text, isNotEmpty);
    }
    for (final bad in [
      r'{"parts":[{"text":"Keep","\u0074ext":"overwrite"}]}',
      '{"parts":[{"text":"Keep","kind":"external","source_ids":["S1"]}]}',
      '{"parts":[{"text":"Keep","kind":"book","source_ids":["S9"]}]}',
      '{"parts":[{"text":"Keep","kind":"book","source_ids":["S1","S1"]}]}',
      '{"parts":[{"text":"Keep","kind":"wrong","source_ids":[]}]}',
    ]) {
      final reader = ChatPreviewDecoder(sources: [source])..add(bad);
      expect(reader.invalid, true, reason: bad);
      expect(reader.blocks.first.text, 'Keep');
      expect(reader.blocks.first.sources, isEmpty);
      reader.add('ignored');
      expect(reader.blocks.first.text, 'Keep');
    }
  });

  test('duplicate root key or later malformed paragraph revokes earlier valid citations', () {
    for (final tail in [
      r',"\u0070arts":[]}',
      ',"status":"answered","status":"partial"}',
      ',"other":true,}',
    ]) {
      final reader = ChatPreviewDecoder(sources: [source])
        ..add(wire.substring(0, wire.length - 1));
      expect(reader.blocks.first.sources, isNotEmpty);
      reader.add(tail);
      expect(reader.invalid, true);
      expect(reader.blocks.every((b) => b.sources.isEmpty), true);
    }
  });

  test('bounds and invalid Unicode stop safely', () {
    for (final invalid in [
      '{"parts":[{"text":"ok\\uDC00',
      '{"parts":[{"text":"ok\\uD800x',
      '{"parts":[{"text":"ok\\q',
      '{"parts":[{"text":"ok\n',
      '{"parts":[{"text":"ok",}]}',
      '{"parts":[{"text":"ok"},]}',
    ]) {
      final reader = ChatPreviewDecoder()..add(invalid);
      expect(reader.invalid, true, reason: invalid);
      expect(reader.blocks.first.text, 'ok');
    }
    final reader = ChatPreviewDecoder()..add('{"parts":[{"text":"ok');
    reader.add('x' * 48000);
    expect(reader.invalid, true);
    expect(reader.blocks.single.text, 'ok');
  });

  test('layout and kind that arrive before text shape the draft', () {
    final reader = ChatPreviewDecoder()
      ..add(
        '{"parts":[{"layout":"item","kind":"interpretation","text":"**Satu',
      );
    expect(reader.blocks.single.layout, ChatAnswerLayout.item);
    expect(reader.blocks.single.kind, ChatAnswerKind.interpretation);
    reader.add('.** isi"},{"layout":"quote","kind":"external","text":"x');
    // Kutipan bukan dari buku jatuh ke paragraf.
    expect(reader.blocks.last.layout, ChatAnswerLayout.paragraph);
    final odd = ChatPreviewDecoder()
      ..add('{"parts":[{"layout":"huh","kind":"???","text":"ok');
    expect(odd.invalid, isFalse);
    expect(odd.blocks.single.layout, ChatAnswerLayout.paragraph);
    expect(odd.blocks.single.kind, ChatAnswerKind.book);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/chapter_extractor.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/chat_retrieval.dart';
import 'package:luma/domain/models/book_chat.dart';

import '../support/book_chat_recovery.dart' as spike;
import '../support/book_chat_validation3.dart' as fixture;

void main() {
  const book = (bookId: 1, contentRevision: 2);
  const ChatParagraph paragraph = (
    book: book,
    chapterId: 4,
    paragraphIndex: 3,
    text: 'A 🌿 garden belongs to the keeper.',
  );
  final paragraphs = {(chapterId: 4, paragraphIndex: 3): paragraph};
  SourceAnchor anchor({int start = 0, int? end}) => SourceAnchor(
    book: book,
    chapterId: 4,
    paragraphIndex: 3,
    start: start,
    end: end ?? paragraph.text.length,
    paragraphHash: chatTextHash(paragraph.text),
    snapshot: paragraph.text.substring(start, end),
  );
  ChatSource source(String id) =>
      ChatSource(id: id, chapterTitle: 'IV', anchors: [anchor()]);

  test('accepted rewrite and selector systems remain frozen', () {
    expect(chatRewriteSystem, spike.searchRewriteSystem);
    expect(chatSelectionSystem, spike.recoverySelectionSystem);
    expect(fixture.verifyValidation3(), isNotEmpty);
  });

  test('replay manifests preserve original spike evidence byte-for-byte', () {
    for (final name in [
      'book_chat_heldout_protocol_v1.json',
      'book_chat_validation2_protocol.json',
      'book_chat_validation3_protocol.json',
    ]) {
      final current =
          jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map;
      final replay = current['replayOf'] as Map;
      final raw = File(replay['file'] as String).readAsStringSync();
      expect(chatTextHash(raw), replay['sha256']);
      final original = jsonDecode(raw) as Map;
      final field = current.containsKey('sourceHashes')
          ? 'sourceHashes'
          : 'sha256';
      final originalHashes = Map.of(original[field] as Map)
        ..remove('lib/data/services/openrouter_service.dart');
      final currentHashes = Map.of(current[field] as Map)
        ..remove('lib/data/services/openrouter_service.dart');
      expect(currentHashes, originalHashes);
      expect(
        current['thresholds'] ?? current['thresholdsPerRun'],
        original['thresholds'] ?? original['thresholdsPerRun'],
      );
    }
  });

  test('production chunks match every bilingual spike book range and text', () {
    final frozen = fixture.validation3Corpus();
    for (final (b, name) in fixture.validation3Books.indexed) {
      final ref = (bookId: b + 1, contentRevision: 1);
      final parsed = extractChapters(
        parseEpub(File('test/fixtures/$name.epub').readAsBytesSync()),
      );
      final indexed = <ChatIndexedParagraph>[];
      final titles = <int, String>{};
      for (final (i, chapter) in parsed.chapters.indexed) {
        titles[i + 1] = chapter.title;
        for (final (j, p) in chapter.paragraphs.indexed) {
          indexed.add((
            paragraph: (
              book: ref,
              chapterId: i + 1,
              paragraphIndex: j,
              text: p.text,
            ),
            chapterTitle: chapter.title,
            groupIndex: chapter.groups[j],
          ));
        }
      }
      final actual = chatChunks(indexed, ref);
      final expected = frozen.chunks
          .where((s) => s.passage.book == name)
          .toList();
      expect(actual.length, expected.length, reason: name);
      for (var i = 0; i < actual.length; i++) {
        expect(actual[i].text, expected[i].passage.text);
        expect(actual[i].chapterTitle, expected[i].passage.chapter);
        expect(
          actual[i].anchors.map(
            (a) => (titles[a.chapterId], a.paragraphIndex, a.start, a.end),
          ),
          expected[i].ranges.map(
            (r) => (r.paragraph.chapter, r.paragraph.index, r.start, r.end),
          ),
        );
      }
    }
  });

  test(
    'window boundaries preserve Unicode, overlap and whole quote coverage',
    () {
      final text = '🌿 word ' * 700;
      final ChatParagraph p = (
        book: book,
        chapterId: 4,
        paragraphIndex: 3,
        text: text,
      );
      final chunks = chatChunks([
        (paragraph: p, chapterTitle: 'IV', groupIndex: 1),
      ], book);
      final map = {(chapterId: 4, paragraphIndex: 3): p};
      validateChatSources(chunks, book, map);
      expect(chunks.length, greaterThan(1));
      expect(chunks.first.anchors.first.start, 0);
      expect(chunks.last.anchors.last.end, text.length);
      for (var i = 1; i < chunks.length; i++) {
        expect(
          chunks[i].anchors.first.start,
          lessThan(chunks[i - 1].anchors.last.end),
        );
      }
      final a = SourceAnchor(
        book: book,
        chapterId: 4,
        paragraphIndex: 3,
        start: 1500,
        end: 2100,
        paragraphHash: chatTextHash(text),
        snapshot: text.substring(1500, 2100),
      );
      final selected = chatQuoteSources(chunks, ChatQuote(anchors: [a]));
      expect(selected.length, greaterThan(1));
      expect(
        selected.map((s) => s.text).join(),
        contains(a.snapshot.substring(0, 100)),
      );
      expect(
        () => chatChunks(
          [(paragraph: paragraph, chapterTitle: 'IV', groupIndex: 1)],
          (bookId: 2, contentRevision: 2),
        ),
        throwsFormatException,
      );
    },
  );

  test('BM25, cosine and RRF vote order, unique IDs, pinned quotes, top40', () {
    final a = source('S1'), b = source('S2'), c = source('S3');
    expect(
      chatFuseRanks([
        [a, a, b],
        [b, a],
        [b, c],
      ]).map((s) => s.id),
      ['S2', 'S1', 'S3'],
    );
    expect(
      chatFuseRanks(
        [
          [a],
          [a],
          [a],
        ],
        quoteSources: [c, b],
      ).map((s) => s.id),
      ['S3', 'S2', 'S1'],
    );
    final many = List.generate(70, (i) => source('S${i + 1}'));
    expect(chatFuseRanks([many, many, many]), hasLength(40));
    expect(ChatLexicalIndex([a]).search('keeper').single, a);
    expect(ChatLexicalIndex([a]).search('unknown'), isEmpty);
    expect(
      chatDenseSearch(
        [a, b],
        [
          Float32List.fromList([1, 0]),
          Float32List.fromList([0, 1]),
        ],
        Float32List.fromList([0, 1]),
      ).first,
      b,
    );
    expect(
      () => chatDenseSearch([a], [Float32List(3)], Float32List(2)),
      throwsFormatException,
    );
  });

  test(
    'selector rejects invented/duplicate IDs and keeps quote before budget fit',
    () {
      final candidates = [source('S1'), source('S2')];
      expect(
        parseChatSelection('{"selected":[2]}', candidates, [candidates.first]),
        candidates,
      );
      for (final raw in [
        '{}',
        '{"selected":[0]}',
        '{"selected":[3]}',
        '{"selected":[1,1]}',
        '{"selected":["1"]}',
      ]) {
        expect(
          () => parseChatSelection(raw, candidates, []),
          throwsFormatException,
        );
      }
      expect(
        () => chatRetrievalUser({'q': '🌿' * 100}, 'system', 100),
        throwsFormatException,
      );
    },
  );

  test('embedding parser enforces model, index, dimension and finite norm', () {
    const model = ChatEmbeddingModel.openaiLarge;
    final vector = List<num>.filled(model.dimensions, 0)
      ..[0] = 3
      ..[1] = 4;
    Map<String, Object> body(
      Object data, {
      String name = 'text-embedding-3-large',
    }) => {'model': name, 'data': data};
    final row = {'index': 0, 'embedding': vector};
    final v = parseChatEmbeddings(body([row]), 1, model).single;
    expect(v[0], closeTo(.6, .00001));
    expect(v[1], closeTo(.8, .00001));
    for (final bad in [
      body([row], name: 'qwen/qwen3-embedding-8b'),
      body([row, row]),
      body([
        {'index': 1, 'embedding': vector},
      ]),
      body([
        {
          'index': 0,
          'embedding': [1],
        },
      ]),
      body([
        {'index': 0, 'embedding': List.filled(model.dimensions, 0)},
      ]),
      body([
        {
          'index': 0,
          'embedding': [...vector.take(model.dimensions - 1), double.nan],
        },
      ]),
    ]) {
      expect(() => parseChatEmbeddings(bad, 1, model), throwsFormatException);
    }
  });

  test('incremental JSON never exposes sources until final validation', () {
    final s = source('S1');
    final prompt = ChatPrompt(user: '{}', sources: [s], historyTurnIds: []);
    final raw = jsonEncode({
      'status': 'answered',
      'claims': [
        {
          'text': 'Taman 🌿',
          'source_ids': ['S1'],
        },
      ],
      'note': '',
    });
    final decoder = ChatAnswerDecoder(
      prompt: prompt,
      current: book,
      paragraphs: paragraphs,
    );
    for (final rune in raw.runes) {
      decoder.add(String.fromCharCode(rune));
    }
    expect(decoder.finish().blocks.single.sources.single, s);
    for (final invalid in [
      raw.substring(0, raw.length - 1),
      raw.replaceAll('S1', 'S999'),
      '$raw extra',
    ]) {
      final d = ChatAnswerDecoder(
        prompt: prompt,
        current: book,
        paragraphs: paragraphs,
      )..add(invalid);
      expect(d.finish, throwsFormatException);
    }
    final foreign = ChatAnswerDecoder(
      prompt: prompt,
      current: (bookId: 2, contentRevision: 2),
      paragraphs: paragraphs,
    )..add(raw);
    expect(foreign.finish, throwsFormatException);
    final changed = {
      ...paragraphs,
      (chapterId: 4, paragraphIndex: 3): (
        book: book,
        chapterId: 4,
        paragraphIndex: 3,
        text: 'Changed',
      ),
    };
    final stale = ChatAnswerDecoder(
      prompt: prompt,
      current: book,
      paragraphs: changed,
    )..add(raw);
    expect(stale.finish, throwsFormatException);
  });
}

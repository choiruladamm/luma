import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_dense.dart';
import '../support/book_chat_embedding_fallback.dart';
import '../support/book_chat_gold.dart';
import '../support/book_chat_heldout.dart';
import '../support/book_chat_retrieval.dart';
import '../support/book_chat_validation2.dart';

void main() {
  test('consumed validation2 candidate depth diagnostic, no API', () {
    final data = validation2Corpus();
    final corpus = data.chunks.map((c) => c.passage).toList();
    final byId = {for (final c in data.chunks) c.passage.id: c};
    final cache = LargeEmbeddingCache(
      File('/tmp/luma-book-chat-validation2-large.jsonl'),
    );
    final gold = readGold(validation2File);
    final rows = <Map<String, dynamic>>[];
    for (final job in validation2Inputs()) {
      final c = job.input;
      final g = gold.firstWhere((g) => g.id == c.id);
      final ranked = denseSearch(
        corpus,
        cache,
        cache.vector(
          embeddingQueryForModel(
            heldoutQuery(c, data.chunks),
            largeEmbeddingModel,
          ),
        ),
        c.book,
        k: corpus.length,
      );
      if (g.facts.isEmpty) continue;
      final firstComplete = List.generate(ranked.length, (i) => i + 1)
          .firstWhere(
            (n) => rangeRecall(g, ranked.take(n).map((p) => byId[p.id]!)) == 1,
            orElse: () => -1,
          );
      rows.add({'id': c.id, 'firstCompleteRank': firstComplete});
    }
    File('/tmp/luma-recovery-depth.json').writeAsStringSync(jsonEncode(rows));
    // ignore: avoid_print
    print(jsonEncode(rows));
    expect(rows.length, 30);
  }, skip: Platform.environment['BOOK_CHAT_RECOVERY_REPLAY'] != '1');
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/ai_prompt.dart';
import 'package:luma/domain/models/ai_model.dart';

/// Talks to the real OpenRouter (costs a fraction of a cent). Skipped unless
/// a key is given:
///   make live            (key from .env at the repo root, gitignored)
///   make live m=qwen/qwen3.8-flash
void main() {
  final key = Platform.environment['OPENROUTER_API_KEY'];
  final picked = Platform.environment['OPENROUTER_MODEL'] ?? '';
  final model = picked.isEmpty ? defaultAiModel : picked;

  test(
    'a sample group comes back translated and explained ($model)',
    () async {
      final service = OpenRouterService();
      expect(await service.checkKey(key!), isTrue);
      final reply = await service.explain(
        apiKey: key,
        model: model,
        context: [
          'It is a truth universally acknowledged, that a single man in '
              'possession of a good fortune, must be in want of a wife.',
        ],
        target: [
          'However little known the feelings or views of such a man may be '
              'on his first entering a neighbourhood, this truth is so well '
              'fixed in the minds of the surrounding families, that he is '
              'considered the rightful property of some one or other of '
              'their daughters.',
          '"My dear Mr. Bennet," said his lady to him one day, "have you '
              'heard that Netherfield Park is let at last?"',
        ],
      );
      expect(reply.translations, hasLength(2));
      expect(reply.meaning, isNotEmpty);
      // ignore: avoid_print
      print('${reply.translations.join('\n')}\n— ${reply.meaning}');
    },
    skip: key == null ? 'set OPENROUTER_API_KEY to run' : false,
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'The Enchiridion streams in sections, knowing the book ($model)',
    () async {
      final watch = Stopwatch()..start();
      int? first;
      final parts = await OpenRouterService()
          .explainStream(
            apiKey: key,
            model: model,
            book: (title: 'The Enchiridion', author: 'Epictetus', chapter: 'I'),
            context: const [],
            target: const [
              'Of things some are in our power, and others are not. In our '
                  'power are opinion, movement towards a thing, desire, '
                  'aversion (turning from a thing); and in a word, whatever '
                  'are our own acts: not in our power are the body, property, '
                  'reputation, offices (magisterial power), and in a word, '
                  'whatever are not our own acts.',
              'And the things in our power are by nature free, not subject '
                  'to restraint nor hindrance: but the things not in our power '
                  'are weak, slavish, subject to restraint, in the power of '
                  'others.',
            ],
          )
          .map((p) {
            first ??= watch.elapsedMilliseconds;
            return p;
          })
          .toList();
      final reply = parseAiSections(parts.join(), 2);
      expect(reply.translations, hasLength(2));
      // ignore: avoid_print
      print(
        '${parts.length} parts, first after ${first}ms, '
        'all after ${watch.elapsedMilliseconds}ms\n${reply.translations.join('\n')}\n— ${reply.meaning}',
      );
    },
    skip: key == null ? 'set OPENROUTER_API_KEY to run' : false,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

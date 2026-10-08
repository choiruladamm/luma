import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/ai_prompt.dart';
import 'package:luma/domain/breakdown_prompt.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/breakdown.dart';

/// Talks to the real OpenRouter (costs a fraction of a cent). Skipped unless
/// a key is given:
///   make live            (key from .env at the repo root, gitignored)
///   make live m=qwen/qwen3.8-flash
void main() {
  final key = Platform.environment['OPENROUTER_API_KEY'];
  final picked = Platform.environment['OPENROUTER_MODEL'] ?? '';
  final model = picked.isEmpty ? defaultAiModel : picked;
  final skip = key == null ? 'set OPENROUTER_API_KEY to run' : false;

  for (final c in bedahinCases) {
    test(
      'Bedahin: ${c.name} ($model)',
      () async {
        final watch = Stopwatch()..start();
        final b = await liveBreakdown(key!, model, c);
        // ignore: avoid_print
        print(
          '${c.name}: ${b.sections.length} sections '
          '${[for (final s in b.sections) 'K${s.from}-K${s.to}']}, '
          '${b.terms.length} terms, links ${[for (final l in b.links) l.chapter ?? 'LANJUT']}, '
          'practice ${b.practice != null}, ${watch.elapsedMilliseconds}ms',
        );
        c.check(b);
      },
      skip: skip,
      timeout: const Timeout(Duration(seconds: 180)),
    );
  }

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
    skip: skip,
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
    skip: skip,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

/// Bedahin sample (#61): the group, its book, and what the answer must show.
typedef BedahinCase = ({
  String name,
  AiBook book,
  List<String> chapters,
  List<String> context,
  List<String> original,
  List<String> next,
  void Function(Breakdown) check,
});

const _enchiridion = (
  title: 'The Enchiridion',
  author: 'Epictetus',
  chapter: '',
);
final _enchiridionChapters = [
  'NOTE ON THE TEXT',
  'INTRODUCTION',
  'SELECTED BIBLIOGRAPHY',
  for (var i = 1; i <= 51; i++) _roman(i),
];

String _roman(int n) {
  const map = {50: 'L', 40: 'XL', 10: 'X', 9: 'IX', 5: 'V', 4: 'IV', 1: 'I'};
  final out = StringBuffer();
  for (final MapEntry(:key, :value) in map.entries) {
    for (; n >= key; n -= key) {
      out.write(value);
    }
  }
  return '$out';
}

final bedahinCases = <BedahinCase>[
  (
    name: 'Enchiridion XXIV (4 steps)',
    book: (
      title: _enchiridion.title,
      author: _enchiridion.author,
      chapter: 'XXIV',
    ),
    chapters: _enchiridionChapters,
    context: const [
      'If you ever happen to turn your attention to externals, for the '
          'pleasure of anyone, be assured that you have ruined your scheme of '
          'life. Be content, then, in everything, with being a philosopher; '
          'and if you wish to seem so likewise to anyone, appear so to '
          'yourself, and it will suffice you.',
    ],
    original: const [
      'Let not such considerations as these distress you: “I shall live in '
          'discredit and be nobody anywhere.” For if discredit be an evil, '
          'you can no more be involved in evil through another than in '
          'baseness. Is it any business of yours, then, to get power or to be '
          'admitted to an entertainment? By no means. How then, after all, is '
          'this discredit? And how it is true that you will be nobody '
          'anywhere when you ought to be somebody in those things only which '
          'are within your own power, in which you may be of the greatest '
          'consequence? “But my friends will be unassisted.” What do you mean '
          'by “unassisted”? They will not have money from you, nor will you '
          'make them Roman citizens. Who told you, then, that these are among '
          'the things within our own power, and not rather the affairs of '
          'others? And who can give to another the things which he himself '
          'has not? “Well, but get them, then, that we too may have a '
          'share.” If I can get them with the preservation of my own honor '
          'and fidelity and self-respect, show me the way and I will get '
          'them; but if you require me to lose my own proper good, that you '
          'may gain what is no good, consider how unreasonable and foolish '
          'you are. Besides, which would you rather have, a sum of money or a '
          'faithful and honorable friend? Rather assist me, then, to gain '
          'this character than require me to do those things by which I may '
          'lose it. Well, but my country, say you, as far as depends upon me, '
          'will be unassisted. Here, again, what assistance is this you mean? '
          'It will not have porticos nor baths of your providing? And what '
          'signifies that? Why, neither does a smith provide it with shoes, '
          'nor a shoemaker with arms. It is enough if everyone fully performs '
          'his own proper business. And were you to supply it with another '
          'faithful and honorable citizen, would not he be of use to it? Yes. '
          'Therefore neither are you yourself useless to it. “What place, '
          'then,” say you, “shall I hold in the state?” Whatever you can hold '
          'with the preservation of your fidelity and honor. But if, by '
          'desiring to be useful to that, you lose these, how can you serve '
          'your country when you have become faithless and shameless?',
    ],
    next: const [],
    check: (b) {
      expect(b.sections.length, greaterThanOrEqualTo(3));
      expect(b.links.where((l) => l.chapter == null), isEmpty);
    },
  ),
  (
    name: 'Enchiridion V (1 idea)',
    book: (
      title: _enchiridion.title,
      author: _enchiridion.author,
      chapter: 'V',
    ),
    chapters: _enchiridionChapters,
    context: const [],
    original: const [
      'Men are disturbed not by things, but by the views which they take of '
          'things. Thus death is nothing terrible, else it would have '
          'appeared so to Socrates. But the terror consists in our notion of '
          'death, that it is terrible. When, therefore, we are hindered or '
          'disturbed, or grieved, let us never impute it to others, but to '
          'ourselves—that is, to our own views. It is the action of an '
          'uninstructed person to reproach others for his own misfortunes; of '
          'one entering upon instruction, to reproach himself; and one '
          'perfectly instructed, to reproach neither others nor himself.',
    ],
    next: const [],
    check: (b) => expect(b.sections.length, lessThanOrEqualTo(2)),
  ),
  (
    name: 'Meditations I (continues)',
    book: (
      title: 'Meditations',
      author: 'Marcus Aurelius',
      chapter: 'THE FIRST BOOK',
    ),
    chapters: const [
      'INTRODUCTION',
      'HIS FIRST BOOK concerning HIMSELF:',
      'THE FIRST BOOK',
      'THE SECOND BOOK',
      'THE THIRD BOOK',
      'THE FOURTH BOOK',
      'THE FIFTH BOOK',
      'THE SIXTH BOOK',
      'THE SEVENTH BOOK',
      'THE EIGHTH BOOK',
      'THE NINTH BOOK',
      'THE TENTH BOOK',
      'THE ELEVENTH BOOK',
      'THE TWELFTH BOOK',
      'APPENDIX',
      'NOTES',
      'GLOSSARY',
    ],
    context: const [],
    original: const [
      'I. Of my grandfather Verus I have learned to be gentle and meek, and '
          'to refrain from all anger and passion. From the fame and memory of '
          'him that begot me I have learned both shamefastness and manlike '
          'behaviour. Of my mother I have learned to be religious, and '
          'bountiful; and to forbear, not only to do, but to intend any evil; '
          'to content myself with a spare diet, and to fly all such excess as '
          'is incidental to great wealth. Of my great-grandfather, both to '
          'frequent public schools and auditories, and to get me good and '
          'able teachers at home; and that I ought not to think much, if upon '
          'such occasions, I were at excessive charges.',
    ],
    next: const [
      'II. Of him that brought me up, not to be fondly addicted to either of '
          'the two great factions of the coursers in the circus, called '
          'Prasini, and Veneti: nor in the amphitheatre partially to favour '
          'any of the gladiators, or fencers, as either the Parmularii, or '
          'the Secutores. Moreover, to endure labour; nor to need many '
          'things; when I have anything to do, to do it myself rather than by '
          'others; not to meddle with many businesses; and not easily to '
          'admit of any slander.',
    ],
    check: (b) => expect(b.links.where((l) => l.chapter == null), isNotEmpty),
  ),
  (
    name: 'Pride and Prejudice 1 (narrative)',
    book: (
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      chapter: 'Chapter 1',
    ),
    chapters: [for (var i = 1; i <= 61; i++) 'Chapter $i'],
    context: const [
      'It is a truth universally acknowledged, that a single man in '
          'possession of a good fortune, must be in want of a wife.',
    ],
    original: const [
      '“My dear Mr. Bennet,” said his lady to him one day, “have you heard '
          'that Netherfield Park is let at last?”',
      'Mr. Bennet replied that he had not.',
      '“But it is,” returned she; “for Mrs. Long has just been here, and she '
          'told me all about it.”',
    ],
    next: const ['Mr. Bennet made no answer.'],
    check: (b) => expect(b.practice, isNull),
  ),
];

/// Quick meaning first (Bedahin opens after it), then the breakdown.
Future<Breakdown> liveBreakdown(String key, String model, BedahinCase c) async {
  final service = OpenRouterService();
  final reply = await service.explain(
    apiKey: key,
    model: model,
    book: c.book,
    context: c.context,
    target: c.original,
  );
  final input = BreakdownInput(
    book: c.book,
    chapters: c.chapters,
    chapter: c.chapters.indexOf(c.book.chapter) + 1,
    context: c.context,
    original: c.original,
    translations: reply.translations,
    meaning: reply.meaning,
    next: c.next,
  );
  final content =
      (await service
              .breakdownStream(apiKey: key, model: model, input: input)
              .toList())
          .join();
  try {
    return parseBreakdown(content, input);
  } on AiException {
    // ignore: avoid_print
    print('INVALID ${c.name}:\n${breakdownUserPrompt(input)}\n---\n$content');
    rethrow;
  }
}

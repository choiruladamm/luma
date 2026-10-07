import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/ai_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';

void main() {
  group('parseAiReply', () {
    const ok = '{"translations": ["Satu.", "Dua."], "meaning": "Gitu deh."}';

    test('plain JSON', () {
      final r = parseAiReply(ok, 2);
      expect(r.translations, ['Satu.', 'Dua.']);
      expect(r.meaning, 'Gitu deh.');
    });

    test('code fence and chatter around it are stripped', () {
      final r = parseAiReply('Here you go:\n```json\n$ok\n```\nEnjoy!', 2);
      expect(r.translations, hasLength(2));
    });

    Matcher invalid = throwsA(
      isA<AiException>().having(
        (e) => e.error,
        'error',
        AiError.invalidResponse,
      ),
    );

    test('count mismatch is invalid', () {
      expect(() => parseAiReply(ok, 3), invalid);
      expect(() => parseAiReply(ok, 1), invalid);
    });

    test('not JSON, broken JSON, wrong shapes are invalid', () {
      expect(() => parseAiReply('Maaf, saya tidak bisa.', 1), invalid);
      expect(() => parseAiReply('{"translations": ["a"', 1), invalid);
      expect(
        () => parseAiReply('{"translations": "a", "meaning": "m"}', 1),
        invalid,
      );
      expect(
        () => parseAiReply('{"translations": [1], "meaning": "m"}', 1),
        invalid,
      );
      expect(() => parseAiReply('{"translations": ["a"]}', 1), invalid);
      expect(
        () => parseAiReply('{"translations": ["a"], "meaning": " "}', 1),
        invalid,
      );
    });
  });

  test('user prompt: context, then numbered target', () {
    expect(
      aiUserPrompt(context: ['C1', 'C2'], target: ['T1', 'T2']),
      'KONTEKS (paragraf sebelumnya):\nC1\n\nC2\n\nTARGET:\n[1] T1\n[2] T2',
    );
    expect(aiUserPrompt(context: [], target: ['T1']), 'TARGET:\n[1] T1');
  });

  test('user prompt: the book and chapter come first; no author, no line', () {
    expect(
      aiUserPrompt(
        book: (title: 'The Enchiridion', author: 'Epictetus', chapter: 'I'),
        context: [],
        target: ['T1'],
      ),
      'BUKU: The Enchiridion, Epictetus\nBAB: I\n\nTARGET:\n[1] T1',
    );
    expect(
      aiUserPrompt(
        book: (title: 'Walden', author: '  ', chapter: ''),
        context: ['C'],
        target: ['T1'],
      ),
      'BUKU: Walden\n\nKONTEKS (paragraf sebelumnya):\nC\n\nTARGET:\n[1] T1',
    );
  });

  test('both system prompts carry the style rules', () {
    for (final p in [aiSystemPrompt, aiStreamSystemPrompt]) {
      expect(p, contains('BUKU dan BAB'));
      expect(p, contains('bahasanya kuno'));
    }
  });

  group('parseAiDraft (streaming)', () {
    const full = '[T1]\nSatu dua.\n[T2]\nTiga.\n[MAKNA]\nGitu deh.';

    test('grows section by section', () {
      expect(parseAiDraft('').translations, isEmpty);
      expect(parseAiDraft('[T1]\nSat').translations, ['Sat']);
      final mid = parseAiDraft('[T1]\nSatu dua.\n[T2]\nTi');
      expect(mid.translations, ['Satu dua.', 'Ti']);
      expect(mid.meaning, isNull);
      final last = parseAiDraft(full);
      expect(last.translations, ['Satu dua.', 'Tiga.']);
      expect(last.meaning, 'Gitu deh.');
    });

    test('a marker cut at a chunk boundary is held back', () {
      for (final cut in ['[', '[T', '[T2', '[MAK', '[MAKNA']) {
        final d = parseAiDraft('[T1]\nSatu.\n$cut');
        expect(d.translations, ['Satu.'], reason: cut);
        expect(d.meaning, isNull, reason: cut);
      }
      expect(parseAiDraft('[T').translations, isEmpty);
    });

    test('text before the first marker is dropped', () {
      expect(parseAiDraft('Oke, ini dia:\n[T1]\nSatu.').translations, [
        'Satu.',
      ]);
    });

    test('take reveals letters in reading order', () {
      final d = parseAiDraft(full); // 9 + 5 + 9 letters
      expect(d.length, 23);
      expect(d.take(4).translations, ['Satu']);
      expect(d.take(11).translations, ['Satu dua.', 'Ti']);
      expect(d.take(11).meaning, isNull);
      expect(d.take(16).meaning, 'Gi');
      expect(d.take(99).meaning, 'Gitu deh.');
      expect(d.take(0).translations, isEmpty);
    });
  });

  group('parseAiSections', () {
    Matcher invalid = throwsA(
      isA<AiException>().having(
        (e) => e.error,
        'error',
        AiError.invalidResponse,
      ),
    );

    test('a complete answer', () {
      final r = parseAiSections('[T1]\nSatu.\n[T2]\nDua.\n[MAKNA]\nM.\n', 2);
      expect(r.translations, ['Satu.', 'Dua.']);
      expect(r.meaning, 'M.');
    });

    test('marker on the same line as its text still counts', () {
      expect(parseAiSections('[T1] Satu.\n[MAKNA] M.', 1).meaning, 'M.');
    });

    test('wrong count, order, missing meaning or empty part is invalid', () {
      expect(() => parseAiSections('[T1]\nA\n[MAKNA]\nM', 2), invalid);
      expect(() => parseAiSections('[T2]\nA\n[T1]\nB\n[MAKNA]\nM', 2), invalid);
      expect(() => parseAiSections('[T1]\nA', 1), invalid);
      expect(() => parseAiSections('[T1]\n\n[MAKNA]\nM', 1), invalid);
      expect(() => parseAiSections('{"translations": []}', 1), invalid);
    });
  });
}

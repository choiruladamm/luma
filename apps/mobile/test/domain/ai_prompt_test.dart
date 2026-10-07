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
}

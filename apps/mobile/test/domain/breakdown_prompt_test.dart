import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/breakdown_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';

/// 3 paragraphs, 6 sentences: K1-K2 | K3 | K4-K6.
const input = BreakdownInput(
  book: (title: 'The Enchiridion', author: 'Epictetus', chapter: 'XXIV'),
  chapters: ['I', 'V', 'XVII', 'XXIV'],
  chapter: 4,
  context: ['Before.'],
  original: ['P one.', 'P two.', 'P three.'],
  translations: [
    'Jangan resah. Kamu bukan siapa-siapa.',
    '“Tapi teman-temanku tidak terbantu.”',
    'Negerimu gak punya serambi. Terus kenapa? Cukup tiap orang kerja.',
  ],
  meaning: 'Integritas lebih penting.',
  next: ['Is anyone preferred before you?'],
);

String section(String range, {String m = 'M', String l = 'L'}) =>
    '[BAGIAN $range]\nJudul: T $range\nMaksudnya: $m\nLogikanya: $l\n';

final invalid = throwsA(
  isA<AiException>().having((e) => e.error, 'error', AiError.invalidResponse),
);

void main() {
  test('user prompt: book, chapter list, numbered text and sentences', () {
    expect(breakdownUserPrompt(input), '''
BUKU: The Enchiridion, Epictetus
BAB: XXIV
DAFTAR BAB:
[B1] I
[B2] V
[B3] XVII
[B4] XXIV

KONTEKS SEBELUM:
Before.

TEKS ASLI:
[P1] P one.
[P2] P two.
[P3] P three.

TERJEMAHAN (kalimat bernomor):
[P1]
[K1] Jangan resah.
[K2] Kamu bukan siapa-siapa.
[P2]
[K3] “Tapi teman-temanku tidak terbantu.”
[P3]
[K4] Negerimu gak punya serambi.
[K5] Terus kenapa?
[K6] Cukup tiap orang kerja.

MAKSUD (udah dibaca pengguna, jangan diulang/diparafrase):
Integritas lebih penting.

KONTEKS SESUDAH (grup berikutnya di bab ini):
Is anyone preferred before you?''');
  });

  test('user prompt: no context, no next group, no author', () {
    final p = breakdownUserPrompt(
      const BreakdownInput(
        book: (title: 'B', author: null, chapter: ''),
        chapters: ['', 'Two'],
        chapter: 1,
        original: ['X.'],
        translations: ['Y.'],
        meaning: 'Z.',
      ),
    );
    expect(p, startsWith('BUKU: B\nDAFTAR BAB:\n[B1] (tanpa judul)\n[B2] Two'));
    expect(p, isNot(contains('KONTEKS')));
    expect(
      p,
      endsWith(
        'MAKSUD (udah dibaca pengguna, jangan diulang/diparafrase):\nZ.',
      ),
    );
  });

  group('parseBreakdown', () {
    test('sections across paragraphs, all optional blocks', () {
      final b = parseBreakdown(
        'Oke, ini dia:\n'
        '${section('K1-K2')}'
        '${section('K3–K4')}'
        '${section('K5-K6', m: 'Satu\nbaris lagi')}'
        '[ISTILAH]\n'
        'Serambi (stoa) | serambi | Tempat umum.\n'
        '- Romawi | warga Romawi | Status warga.\n'
        'Kurang | kolom\n'
        '[NYAMBUNG]\n'
        'B3 | Metafora aktor | Dari sini.\n'
        'B4 | Diri sendiri | Bab ini.\n'
        'B9 | Gak ada | Bab gak ada.\n'
        'LANJUT | Dari ayahnya | Lanjut.\n'
        'X1 | Ngawur | Ngawur.\n'
        '[PRAKTEK]\n'
        'Tanya dulu.\n',
        input,
      );
      expect(
        [for (final s in b.sections) (s.from, s.to)],
        [(1, 2), (3, 4), (5, 6)],
      );
      expect(b.sections[0].title, 'T K1-K2');
      expect(b.sections[2].meaning, 'Satu baris lagi');
      expect(b.terms, hasLength(2));
      expect(b.terms[0].exact, 'serambi');
      expect(b.terms[0].sentence, 4);
      // Not in the translation: kept, without highlight.
      expect(b.terms[1].label, 'Romawi');
      expect(b.terms[1].exact, isNull);
      expect(b.terms[1].sentence, isNull);
      expect([for (final l in b.links) l.chapter], [3, null]);
      expect(b.links.last.title, 'Dari ayahnya');
      expect(b.practice, 'Tanya dulu.');
    });

    test('one section, optional blocks absent', () {
      final b = parseBreakdown(section('K1-K6'), input);
      expect(b.sections, hasLength(1));
      expect(b.terms, isEmpty);
      expect(b.links, isEmpty);
      expect(b.practice, isNull);
    });

    test('single-sentence range', () {
      final b = parseBreakdown(
        '${section('K1-K2')}${section('K3')}${section('K4-K6')}',
        input,
      );
      expect((b.sections[1].from, b.sections[1].to), (3, 3));
    });

    test('LANJUT is dropped in the last group of a chapter', () {
      const last = BreakdownInput(
        book: (title: 'B', author: null, chapter: 'I'),
        chapters: ['I', 'II'],
        chapter: 1,
        original: ['X.'],
        translations: ['Y.'],
        meaning: 'Z.',
      );
      final b = parseBreakdown(
        '${section('K1-K1')}[NYAMBUNG]\nLANJUT | a | b\nB2 | c | d\nB0 | e | f\n',
        last,
      );
      expect([for (final l in b.links) l.chapter], [2]);
    });

    test('hard failures', () {
      expect(() => parseBreakdown('Gak bisa.', input), invalid);
      expect(() => parseBreakdown('[ISTILAH]\na | b | c', input), invalid);
      // Gap, overlap, past Kn, not reaching Kn, not starting at K1.
      expect(
        () => parseBreakdown('${section('K1-K2')}${section('K4-K6')}', input),
        invalid,
      );
      expect(
        () => parseBreakdown('${section('K1-K3')}${section('K3-K6')}', input),
        invalid,
      );
      expect(() => parseBreakdown(section('K1-K7'), input), invalid);
      expect(() => parseBreakdown(section('K1-K5'), input), invalid);
      expect(() => parseBreakdown(section('K2-K6'), input), invalid);
      expect(
        () => parseBreakdown('${section('K1-K3')}${section('K5-K4')}', input),
        invalid,
      );
      // Empty Maksudnya / Logikanya.
      expect(() => parseBreakdown(section('K1-K6', m: ''), input), invalid);
      expect(
        () => parseBreakdown('[BAGIAN K1-K6]\nJudul: X\nMaksudnya: M', input),
        invalid,
      );
    });

    test('more than 6 sections fails', () {
      final seven = BreakdownInput(
        book: input.book,
        chapters: input.chapters,
        chapter: 4,
        original: const ['x'],
        translations: const ['Satu. Dua. Tiga. Empat. Lima. Enam. Tujuh.'],
        meaning: 'm',
      );
      expect(
        () => parseBreakdown(
          [for (var i = 1; i <= 7; i++) section('K$i-K$i')].join(),
          seven,
        ),
        invalid,
      );
      expect(
        parseBreakdown(
          [for (var i = 1; i <= 5; i++) section('K$i-K$i')].join() +
              section('K6-K7'),
          seven,
        ).sections,
        hasLength(6),
      );
    });
  });

  group('parseBreakdownDraft', () {
    test('a section has its range as soon as its marker is in', () {
      final d = parseBreakdownDraft(
        '[BAGIAN K1-K3]\nJudul: Takut\nMaksudnya: Kehormatan di',
      );
      expect(d.sections, hasLength(1));
      expect((d.sections[0].from, d.sections[0].to), (1, 3));
      expect(d.sections[0].meaning, 'Kehormatan di');
      expect(d.sections[0].logic, '');
    });

    test('a marker cut at the end is held back', () {
      final d = parseBreakdownDraft(
        '[BAGIAN K1-K3]\nJudul: A\nMaksudnya: B\nLogikanya: C\n[BAGIAN K4-K',
      );
      expect(d.sections, hasLength(1));
      expect(d.sections[0].logic, 'C');
      expect(parseBreakdownDraft('[BAG').sections, isEmpty);
    });

    test('a field name cut at the end is held back', () {
      final d = parseBreakdownDraft(
        '[BAGIAN K1-K3]\nJudul: A\nMaksudnya: B\nLogik',
      );
      expect(d.sections[0].meaning, 'B');
    });

    test('optional blocks fill in as they arrive', () {
      final d = parseBreakdownDraft(
        '${section('K1-K6')}[ISTILAH]\nSerambi | serambi | Tempat\nRom',
      );
      expect(d.terms, hasLength(1));
      expect(d.terms[0].explanation, 'Tempat');
      expect(d.practice, isNull);
    });
  });
}

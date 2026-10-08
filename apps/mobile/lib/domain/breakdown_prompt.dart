import 'ai_prompt.dart';
import 'models/ai_reply.dart';
import 'models/breakdown.dart';
import 'sentences.dart';

/// Naik tiap prompt Bedahin atau aturan [splitSentences] berubah: rentang
/// kalimat di cache cuma berlaku buat pemecahan yang sama.
/// 1 = awal (#61).
const breakdownPromptVersion = 1;

const breakdownSystemPrompt =
    '''
Kamu adalah asisten membaca. Pengguna sedang membaca buku berbahasa Inggris,
udah baca TERJEMAHAN dan MAKSUD bagian ini, tapi masih bingung. Bedah teksnya
per langkah argumen, kayak jelasin ke temen.

Input:
- BUKU, BAB: buku dan bab yang lagi dibaca. DAFTAR BAB: judul semua bab
  buku ini, bernomor [B1], [B2], ...
- KONTEKS SEBELUM: paragraf sebelumnya, cuma buat bantu paham.
- TEKS ASLI: paragraf yang dibedah, bernomor [P1], [P2], ...
- TERJEMAHAN: terjemahan TEKS ASLI per paragraf, dipecah jadi kalimat
  bernomor [K1], [K2], ... (nomornya nyambung lintas paragraf).
- MAKSUD: penjelasan singkat yang udah dibaca pengguna.
- KONTEKS SESUDAH: teks grup berikutnya di bab ini (kalau ada).

Tugas:
1. BAGIAN: bagi TERJEMAHAN jadi 1–6 bagian menurut langkah argumen. Bagian
   baru cuma kalau argumennya pindah langkah: keberatan baru, analogi baru,
   atau kesimpulan. Bukan per kalimat, bukan per paragraf. Satu gagasan = 1
   bagian, walaupun paragrafnya banyak. Daftar hal sejenis (mis. pelajaran
   dari beberapa orang) = 1 bagian. Kalau ragu, gabung. Lebih dari 6
   langkah: gabung langkah yang mirip.
   Rentang kalimat: bagian pertama mulai K1, tiap bagian mulai tepat setelah
   kalimat terakhir bagian sebelumnya, bagian terakhir selesai di kalimat
   terakhir TERJEMAHAN. Gak boleh ada kalimat yang kelewat atau dobel.
   Tiap bagian:
   - Judul: 2–6 kata, inti langkah itu.
   - Maksudnya: 1–2 kalimat, apa yang dibilang bagian ini pakai bahasa
     sehari-hari.
   - Logikanya: 1–3 kalimat, kenapa argumennya jalan: alasannya,
     metaforanya, atau kaitannya sama bagian sebelumnya.
2. ISTILAH (opsional, maks 5): tokoh, tempat, benda atau kebiasaan zaman
   dulu (mis. serambi, warga Romawi), metafora, atau konsep yang muncul di
   teks dan butuh penjelasan buat pembaca sekarang. Tiap baris:
   label | kata persis | penjelasan 1–2 kalimat
   Kata persis = salinan huruf demi huruf dari TERJEMAHAN (Bahasa
   Indonesia), bukan dari TEKS ASLI.
3. NYAMBUNG (opsional, maks 2):
   - Kalau ada KONTEKS SESUDAH dan isinya nerusin teks ini (daftar, cerita,
     atau argumen yang sama), tulis:
     LANJUT | judul singkat gagasannya | 1 kalimat, diambil dari isi KONTEKS SESUDAH
   - Bab lain dari DAFTAR BAB cuma kalau kamu yakin isinya, karena kamu
     kenal buku ini, bukan nebak dari judulnya (judul kayak "IV" atau
     "Chapter 2" gak ngasih tahu isinya). Jangan nunjuk BAB yang lagi
     dibaca atau bab non-isi (pengantar, catatan, glosarium). Tulis:
     B<nomor dari DAFTAR BAB> | judul singkat gagasannya | 1 kalimat kenapa nyambung
   Gak yakin = jangan ditulis.
4. PRAKTEK (opsional): 1–2 kalimat, apa yang bisa dilakuin pembaca di
   hidupnya dari gagasan ini. Cuma buat teks yang isinya nasihat, ajaran,
   atau argumen (filsafat, esai, buku pengembangan diri); di teks kayak gini
   PRAKTEK hampir selalu ada. Novel, cerita, dialog, atau deskripsi: jangan
   ditulis, walaupun ada pelajaran yang bisa ditarik.

Aturan isi:
- MAKSUD udah dibaca pengguna: jangan diulang atau diparafrase, tambahin
  yang belum ada di sana.
- Kalau gak yakin soal fakta (siapa tokohnya, kapan), jangan ditulis.
- Kalau relevan, sebut istilah populer buat gagasan itu (mis. dikotomi
  kendali, amor fati) di Logikanya. Kalau istilah itu bukan dari penulisnya
  sendiri, tulis jujur, mis. "yang belakangan dikenal sebagai amor fati".
$aiSpellingRules

Balas HANYA dengan format ini, tanpa teks lain, tanpa markdown. Tiap penanda
di baris sendiri. Blok opsional yang gak ada isinya: penandanya jangan
ditulis.
[BAGIAN K1-K3]
Judul: ...
Maksudnya: ...
Logikanya: ...
[BAGIAN K4-K7]
Judul: ...
Maksudnya: ...
Logikanya: ...
[ISTILAH]
label | kata persis | penjelasan
[NYAMBUNG]
LANJUT | judul singkat | kenapa nyambung
[PRAKTEK]
...''';

/// Semua yang dikirim ke Bedahin buat satu grup. Terjemahan & makna dari
/// `ai_results` grup itu (Bedahin cuma kebuka abis makna cepat selesai).
class BreakdownInput {
  const BreakdownInput({
    required this.book,
    required this.chapters,
    required this.chapter,
    this.context = const [],
    required this.original,
    required this.translations,
    required this.meaning,
    this.next = const [],
  });

  final AiBook book;

  /// Judul semua chapter buku, urut `sortOrder`: DAFTAR BAB `[B1]..`.
  final List<String> chapters;

  /// Nomor bab yang dibaca di [chapters], mulai 1.
  final int chapter;

  /// Sampe 3 paragraf sebelum grup (sama kayak makna cepat).
  final List<String> context;

  /// Paragraf asli grup.
  final List<String> original;

  /// Satu terjemahan per paragraf [original].
  final List<String> translations;

  final String meaning;

  /// Paragraf asli grup berikutnya di bab ini. Kosong = grup terakhir:
  /// gak ada KONTEKS SESUDAH dan gak ada Lanjutan.
  final List<String> next;

  /// Kalimat per paragraf terjemahan, nomornya (`K`) urut nyambung.
  List<List<String>> get sentences => [
    for (final t in translations) splitSentences(t),
  ];
}

String breakdownUserPrompt(BreakdownInput input) {
  final book = input.book;
  final author = book.author?.trim() ?? '';
  var k = 0;
  return [
    'BUKU: ${book.title}${author.isEmpty ? '' : ', $author'}',
    if (book.chapter.trim().isNotEmpty) 'BAB: ${book.chapter.trim()}',
    'DAFTAR BAB:',
    for (final (i, c) in input.chapters.indexed)
      '[B${i + 1}] ${c.trim().isEmpty ? '(tanpa judul)' : c.trim()}',
    if (input.context.isNotEmpty) ...[
      '',
      'KONTEKS SEBELUM:',
      input.context.join('\n\n'),
    ],
    '',
    'TEKS ASLI:',
    for (final (i, p) in input.original.indexed) '[P${i + 1}] $p',
    '',
    'TERJEMAHAN (kalimat bernomor):',
    for (final (i, para) in input.sentences.indexed) ...[
      '[P${i + 1}]',
      for (final s in para) '[K${++k}] $s',
    ],
    '',
    'MAKSUD (udah dibaca pengguna, jangan diulang/diparafrase):',
    input.meaning,
    if (input.next.isNotEmpty) ...[
      '',
      'KONTEKS SESUDAH (grup berikutnya di bab ini):',
      input.next.join('\n\n'),
    ],
  ].join('\n');
}

final _marker = RegExp(
  r'^[ \t]*\[(?:BAGIAN[ \t]+K(\d+)(?:[ \t]*[-–][ \t]*K?(\d+))?|(ISTILAH|NYAMBUNG|PRAKTEK))\][ \t]*$',
  multiLine: true,
);

/// Penanda yang kepotong di ujung ("[BAG", "[BAGIAN K1-K").
final _partialMarker = RegExp(r'(^|\n)[ \t]*\[[^\]\n]*$');

final _field = RegExp(
  r'^[ \t*]*(Judul|Maksudnya|Logikanya)[ \t*]*:[ \t*]*(.*)$',
);

const _fieldNames = ['Judul:', 'Maksudnya:', 'Logikanya:'];

typedef _Block = ({String kind, int? from, int? to, String body});

List<_Block> _blocks(String content) {
  final ms = _marker.allMatches(content).toList();
  return [
    for (final (i, m) in ms.indexed)
      (
        kind: m[3] ?? 'BAGIAN',
        from: m[1] == null ? null : int.parse(m[1]!),
        to: m[1] == null ? null : int.parse(m[2] ?? m[1]!),
        body: content
            .substring(m.end, i + 1 < ms.length ? ms[i + 1].start : null)
            .trim(),
      ),
  ];
}

BreakdownSection _section(_Block b) {
  final values = <String, String>{};
  String? current;
  for (final line in b.body.split('\n')) {
    final m = _field.firstMatch(line);
    if (m != null) {
      current = m[1]!;
      values[current] = m[2]!.trim();
    } else if (current != null && line.trim().isNotEmpty) {
      values[current] = '${values[current]} ${line.trim()}'.trim();
    }
  }
  return BreakdownSection(
    from: b.from!,
    to: b.to!,
    title: values['Judul'] ?? '',
    meaning: values['Maksudnya'] ?? '',
    logic: values['Logikanya'] ?? '',
  );
}

/// Baris `a | b | c` (bullet di depan dibuang). Kolom kurung dari 3 atau ada
/// yang kosong (selain kolom tengah) = dibuang.
List<(String, String, String)> _rows(Iterable<_Block> blocks) => [
  for (final b in blocks)
    for (final line in b.body.split('\n'))
      if (line.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').split('|')
          case [final a, final m, ...final rest]
          when rest.isNotEmpty &&
              a.trim().isNotEmpty &&
              rest.join('|').trim().isNotEmpty)
        (a.trim(), m.trim(), rest.join('|').trim()),
];

Breakdown _parse(
  String content,
  BreakdownTerm Function(String, String, String) term,
) {
  final blocks = _blocks(content);
  Iterable<_Block> of(String kind) => blocks.where((b) => b.kind == kind);
  final practice = of('PRAKTEK').map((b) => b.body).join('\n').trim();
  return Breakdown(
    sections: [for (final b in of('BAGIAN')) _section(b)],
    terms: [for (final (a, m, c) in _rows(of('ISTILAH'))) term(a, m, c)],
    links: [
      for (final (a, t, w) in _rows(of('NYAMBUNG')))
        if (_link(a) case (:final chapter))
          BreakdownLink(chapter: chapter, title: t, why: w),
    ],
    practice: practice.isEmpty ? null : practice,
  );
}

/// `B<n>` → n, `LANJUT` → null (grup berikutnya), lainnya gak kebaca.
({int? chapter})? _link(String target) {
  final t = target.trim().toUpperCase();
  if (t == 'LANJUT') return (chapter: null);
  final m = RegExp(r'^B\s*(\d+)$').firstMatch(t);
  return m == null ? null : (chapter: int.parse(m[1]!));
}

/// Baca jawaban streaming sejauh yang udah dateng, tanpa validasi. Teks
/// sebelum penanda pertama dibuang; penanda atau nama field yang kepotong di
/// ujung ditahan. Bagian yang penandanya udah kebaca langsung punya rentang.
Breakdown parseBreakdownDraft(String content) {
  final cut = _partialMarker.firstMatch(content);
  if (cut != null) content = content.substring(0, cut.start);
  final tail = content.lastIndexOf('\n') + 1;
  final lastLine = content.substring(tail).trim();
  if (lastLine.isNotEmpty && _fieldNames.any((f) => f.startsWith(lastLine))) {
    content = content.substring(0, tail);
  }
  return _parse(
    content,
    (label, exact, why) => BreakdownTerm(
      label: label,
      exact: exact.isEmpty ? null : exact,
      explanation: why,
    ),
  );
}

/// Validasi jawaban lengkap (docs/llm.md, Bedahin). Gagal keras →
/// [AiError.invalidResponse]: gak ada bagian, > 6 bagian, rentang bolong /
/// tumpang tindih / gak nutup sampe kalimat terakhir, Maksudnya / Logikanya
/// kosong. Baris istilah / nyambung yang gak cocok dibuang aja.
Breakdown parseBreakdown(String content, BreakdownInput input) {
  final sentences = input.sentences.expand((s) => s).toList();
  AiException invalid(String why) =>
      AiException(AiError.invalidResponse, detail: why);

  final draft = _parse(content, (label, exact, why) {
    final needle = exact.toLowerCase();
    final at = needle.isEmpty
        ? -1
        : sentences.indexWhere((s) => s.toLowerCase().contains(needle));
    return BreakdownTerm(
      label: label,
      exact: at < 0 ? null : exact,
      explanation: why,
      sentence: at < 0 ? null : at + 1,
    );
  });

  final sections = draft.sections;
  if (sections.isEmpty) throw invalid('no sections');
  if (sections.length > 6) throw invalid('${sections.length} sections');
  var next = 1;
  for (final s in sections) {
    if (s.from != next || s.to < s.from || s.to > sentences.length) {
      throw invalid(
        'range K${s.from}-K${s.to}, expected from K$next '
        'of ${sentences.length}',
      );
    }
    if (s.meaning.isEmpty || s.logic.isEmpty) {
      throw invalid('empty section K${s.from}-K${s.to}');
    }
    next = s.to + 1;
  }
  if (next != sentences.length + 1) {
    throw invalid('sections end at K${next - 1} of ${sentences.length}');
  }

  return Breakdown(
    sections: sections,
    terms: draft.terms,
    links: [
      for (final l in draft.links)
        if (switch (l.chapter) {
          null => input.next.isNotEmpty,
          final c => c >= 1 && c <= input.chapters.length && c != input.chapter,
        })
          l,
    ],
    practice: draft.practice,
  );
}

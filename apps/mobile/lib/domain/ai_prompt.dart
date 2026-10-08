import 'dart:convert';

import 'models/ai_reply.dart';

/// Naik tiap prompt berubah: cache `ai_results` dari versi lebih lama
/// dianggap belum ada, jadi grupnya diterjemahin ulang pas dibuka.
/// 1 = prompt awal, 2 = kenal buku + aturan gaya (#40), 3 = aturan bahasa &
/// makna dari evaluasi 50 potong (#41), 4 = gaya luwes + istilah populer
/// (#28).
const aiPromptVersion = 4;

/// Ejaan + kata ganti, dipake ulang prompt Bedahin (breakdown_prompt.dart).
const aiSpellingRules = '''
- Ejaan Bahasa Indonesia yang benar. Periksa tiap kata: jangan ada kata
  rusak, salah ketik, atau kata bahasa Inggris yang nyelip (kecuali istilah
  kunci yang memang dipertahankan).
- Kata ganti konsisten: "you/thou/thee" = "kamu", "I/me" = "aku", "we" =
  "kita". Jangan pakai "engkau", "Anda", atau "saya".''';

/// Tugas yang sama buat dua format jawaban (docs/llm.md, draft prompt).
const _aiTask =
    '''
Kamu adalah asisten membaca. Pengguna sedang membaca buku berbahasa Inggris
dan ingin memahami bagian TARGET, yang terdiri dari satu atau beberapa
paragraf bernomor. BUKU dan BAB memberi tahu buku apa yang sedang dibaca.

Tugas:
1. Terjemahkan SETIAP paragraf TARGET ke Bahasa Indonesia yang natural,
   bukan kata per kata. Satu paragraf = satu item terjemahan. Jumlah dan
   urutan item harus sama dengan paragraf TARGET.
2. Jelaskan makna TARGET secara keseluruhan dalam 2–4 kalimat Bahasa
   Indonesia yang santai, kayak jelasin ke temen: apa maksud penulis,
   kaitannya dengan konteks sebelumnya, dan istilah sulit kalau ada.

Cara menerjemahkan:
- Pakai BUKU dan BAB untuk memahami konteks: siapa penulisnya, zamannya,
  dan aliran pemikirannya.
- Teks sumber sering terjemahan Inggris lama yang bahasanya kuno. Pahami
  maksudnya, lalu tulis ulang dalam Bahasa Indonesia modern yang enak
  dibaca. Jangan kaku dan jangan kata per kata, tapi maksudnya jangan
  bergeser.
- Istilah kunci (konsep filsafat, nama tokoh, tempat) tetap dipakai; kalau
  perlu, jelaskan singkat di bagian makna.
- Makna menjelaskan maksud penulis dan kaitannya dengan gagasan besar buku
  atau penulisnya, bukan mengulang terjemahan.

Bahasa:
$aiSpellingRules
- Terjemahan setia ke teks: jangan menambah keterangan dalam kurung,
  jangan menebak siapa tokoh yang disebut, jangan menambah kalimat yang
  tidak ada di teks. Penomoran (I., IX.) tetap ditulis.

Makna:
- Maksimal 4 kalimat. Fokus ke gagasan utama potongan ini dan istilah
  sulitnya.
- Kaitkan ke gagasan besar buku hanya kalau benar-benar membantu; jangan
  ditutup kalimat umum seperti "ini inti Stoisisme".
- Jangan mengaku nyambung dengan paragraf lain yang tidak ada di KONTEKS.
  Kalau tidak yakin soal fakta (siapa tokohnya, kapan), jangan ditulis.

Gaya dan istilah:
- Kalimat terjemahan harus luwes seperti tulisan orang Indonesia sekarang:
  pilih kata sehari-hari yang paling umum, jangan meniru urutan kalimat
  bahasa Inggris.
- Untuk konsep kunci, pakai padanan yang paling dikenal pembaca Indonesia
  sekarang (mis. "within our power" = "dalam kendali kita", bukan "dalam
  kuasa kita").
- Di bagian makna, kalau relevan, sebut istilah populer yang dikenal
  pembaca untuk gagasan itu (mis. dikotomi kendali, amor fati, memento
  mori) beserta penjelasan singkat. Kalau istilah itu bukan dari penulisnya
  sendiri, tulis jujur, mis. "sikap yang belakangan dikenal sebagai amor
  fati".

Contoh gaya terjemahan yang diinginkan:
"There are things which are within our power, and there are things which
are beyond our power." → "Ada hal-hal yang berada dalam kendali kita, dan
ada pula hal-hal yang di luar kendali kita."

KONTEKS hanya untuk membantu pemahaman, jangan diterjemahkan.''';

/// Buku yang lagi dibaca, buat prompt: judul, penulis (bisa kosong), bab.
typedef AiBook = ({String title, String? author, String chapter});

/// Prompt sistem, jawaban JSON (jalur tanpa streaming).
const aiSystemPrompt =
    '''
$_aiTask

Balas HANYA dengan JSON, tanpa teks lain:
{"translations": ["...", "..."], "meaning": "..."}''';

/// Prompt sistem buat streaming: teks bersection, jadi tiap paragraf bisa
/// tampil sebelum jawabannya lengkap (spike #34: 30/30 valid).
const aiStreamSystemPrompt =
    '''
$_aiTask

Balas HANYA dengan format ini, tanpa teks lain, tanpa markdown. Tiap
penanda di baris sendiri:
[T1]
terjemahan paragraf 1
[T2]
terjemahan paragraf 2
[MAKNA]
penjelasan makna''';

/// Pesan user: buku + bab (kalau ada), paragraf konteks (kalau ada), terus
/// TARGET bernomor.
String aiUserPrompt({
  AiBook? book,
  required List<String> context,
  required List<String> target,
}) => [
  if (book != null) ...[
    'BUKU: ${book.title}${_filled(book.author) ? ', ${book.author!.trim()}' : ''}',
    if (_filled(book.chapter)) 'BAB: ${book.chapter.trim()}',
    '',
  ],
  if (context.isNotEmpty)
    'KONTEKS (paragraf sebelumnya):\n${context.join('\n\n')}\n',
  'TARGET:',
  for (final (i, p) in target.indexed) '[${i + 1}] $p',
].join('\n');

bool _filled(String? s) => s != null && s.trim().isNotEmpty;

/// Baca jawaban LLM: buang code fence / teks di luar objek JSON, terus cek
/// jumlah terjemahan = [expected]. Gagal → [AiError.invalidResponse].
AiReply parseAiReply(String content, int expected) {
  AiException invalid(String why) =>
      AiException(AiError.invalidResponse, detail: why);

  final start = content.indexOf('{');
  final end = content.lastIndexOf('}');
  if (start < 0 || end < start) throw invalid('no JSON object');
  final Object? json;
  try {
    json = jsonDecode(content.substring(start, end + 1));
  } on FormatException {
    throw invalid('broken JSON');
  }
  if (json is! Map) throw invalid('not an object');
  final translations = json['translations'];
  final meaning = json['meaning'];
  if (translations is! List || translations.any((t) => t is! String)) {
    throw invalid('translations is not a list of strings');
  }
  if (translations.length != expected) {
    throw invalid('${translations.length} translations, expected $expected');
  }
  if (meaning is! String || meaning.trim().isEmpty) {
    throw invalid('meaning missing');
  }
  return AiReply(
    translations: [for (final t in translations) (t as String).trim()],
    meaning: meaning.trim(),
  );
}

/// Jawaban bersection yang lagi ditulis: terjemahan per paragraf (yang
/// terakhir bisa belum utuh), terus makna. Isinya udah tanpa penanda.
class AiDraft {
  const AiDraft({this.translations = const [], this.meaning});

  final List<String> translations;

  /// Null = bagian makna belum mulai.
  final String? meaning;

  /// Jumlah huruf yang bisa ditampilin.
  int get length =>
      translations.fold(0, (n, t) => n + t.length) + (meaning?.length ?? 0);

  /// [n] huruf pertama, urut terjemahan lalu makna.
  AiDraft take(int n) {
    final out = <String>[];
    for (final t in translations) {
      if (n <= 0) return AiDraft(translations: out);
      out.add(n >= t.length ? t : t.substring(0, n));
      n -= t.length;
    }
    final m = meaning;
    if (m == null || n <= 0) return AiDraft(translations: out);
    return AiDraft(
      translations: out,
      meaning: n >= m.length ? m : m.substring(0, n),
    );
  }
}

final _marker = RegExp(r'^[ \t]*\[(T(\d+)|MAKNA)\][ \t]*', multiLine: true);

/// Baris terakhir yang kayak penanda kepotong di batas chunk ("[T", "[MAK").
final _partialMarker = RegExp(r'(^|\n)[ \t]*\[[A-Z0-9]*$');

List<({String label, String text})> _sections(String content) {
  final ms = _marker.allMatches(content).toList();
  return [
    for (final (i, m) in ms.indexed)
      (
        label: m.group(1)!,
        text: content
            .substring(m.end, i + 1 < ms.length ? ms[i + 1].start : null)
            .trim(),
      ),
  ];
}

/// Baca jawaban streaming sejauh yang udah dateng. Teks sebelum penanda
/// pertama dibuang; penanda yang kepotong di ujung ditahan dulu.
AiDraft parseAiDraft(String content) {
  final cut = _partialMarker.firstMatch(content);
  if (cut != null) content = content.substring(0, cut.start);
  final translations = <String>[];
  String? meaning;
  for (final s in _sections(content)) {
    if (s.label == 'MAKNA') {
      meaning = s.text;
    } else if (meaning == null) {
      translations.add(s.text);
    }
  }
  return AiDraft(translations: translations, meaning: meaning);
}

/// Validasi jawaban streaming yang udah lengkap: penanda persis `[T1]` …
/// `[T<expected>]`, `[MAKNA]`, gak ada yang kosong. Gagal →
/// [AiError.invalidResponse].
AiReply parseAiSections(String content, int expected) {
  final sections = _sections(content);
  final labels = [for (final s in sections) s.label];
  final want = [for (var i = 1; i <= expected; i++) 'T$i', 'MAKNA'];
  if (labels.join(',') != want.join(',')) {
    throw AiException(AiError.invalidResponse, detail: 'sections $labels');
  }
  if (sections.any((s) => s.text.isEmpty)) {
    throw const AiException(AiError.invalidResponse, detail: 'empty section');
  }
  return AiReply(
    translations: [for (final s in sections.take(expected)) s.text],
    meaning: sections.last.text,
  );
}

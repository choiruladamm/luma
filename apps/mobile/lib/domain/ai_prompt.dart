import 'dart:convert';

import 'models/ai_reply.dart';

/// Prompt sistem (docs bagian 9, draft prompt).
const aiSystemPrompt = '''
Kamu adalah asisten membaca. Pengguna sedang membaca buku berbahasa Inggris
dan ingin memahami bagian TARGET, yang terdiri dari satu atau beberapa
paragraf bernomor.

Tugas:
1. Terjemahkan SETIAP paragraf TARGET ke Bahasa Indonesia yang natural,
   bukan kata per kata. Satu paragraf = satu item terjemahan. Jumlah dan
   urutan item harus sama dengan paragraf TARGET.
2. Jelaskan makna TARGET secara keseluruhan dalam 2–4 kalimat Bahasa
   Indonesia yang santai, kayak jelasin ke temen: apa maksud penulis,
   kaitannya dengan konteks sebelumnya, dan istilah sulit kalau ada.

KONTEKS hanya untuk membantu pemahaman, jangan diterjemahkan.

Balas HANYA dengan JSON, tanpa teks lain:
{"translations": ["...", "..."], "meaning": "..."}''';

/// Pesan user: paragraf konteks (kalau ada) + TARGET bernomor.
String aiUserPrompt({
  required List<String> context,
  required List<String> target,
}) => [
  if (context.isNotEmpty)
    'KONTEKS (paragraf sebelumnya):\n${context.join('\n\n')}\n',
  'TARGET:',
  for (final (i, p) in target.indexed) '[${i + 1}] $p',
].join('\n');

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

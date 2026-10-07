/// Satu grup paragraf: chapter (id stabil) + `groupIndex`. Record, jadi
/// `==`/`hashCode` per nilai, aman jadi kunci family provider.
typedef GroupRef = ({int chapterId, int groupIndex});

/// Jawaban LLM buat satu grup (docs bagian 9).
class AiReply {
  const AiReply({required this.translations, required this.meaning});

  /// Satu terjemahan per paragraf TARGET, urut.
  final List<String> translations;

  /// Penjelasan makna seluruh grup.
  final String meaning;
}

enum AiError {
  /// API key belum diisi: API gak dipanggil.
  noApiKey,

  /// Lewat ±30 detik.
  timeout,

  /// Gak nyambung ke OpenRouter (offline, DNS, dll).
  network,

  /// Status HTTP bukan 2xx; liat [AiException.status].
  http,

  /// Bukan JSON yang diminta, atau jumlah terjemahan gak cocok.
  invalidResponse,
}

class AiException implements Exception {
  const AiException(this.error, {this.status, this.detail});

  final AiError error;

  /// Status HTTP buat [AiError.http] (401 = key ditolak, 402 = saldo abis).
  final int? status;
  final String? detail;

  @override
  String toString() =>
      'AiException(${error.name}${status == null ? '' : ' $status'}'
      '${detail == null ? '' : ': $detail'})';
}

/// Tahap jawaban streaming satu grup (board "Artinya streaming · perilaku").
enum AiPhase {
  /// 1 · Nunggu token pertama.
  waiting,

  /// 2 · Nulis terjemahan, paragraf masuk berurutan.
  translating,

  /// 3 · Terjemahan lengkap, lagi nulis makna.
  meaning,

  /// 4 · Lengkap, valid, udah di-cache.
  done,

  /// 5 · 15 detik tanpa token. Request tetep jalan.
  slow,

  /// 6 · Putus / mandek di tengah; yang udah masuk tetep ada.
  cut,

  /// Gagal sebelum ada token (gak ada key, timeout 30 detik, HTTP, dll).
  failed,
}

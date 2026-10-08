/// Tahap Bedahin satu grup (#62). Ambang waktunya sama kayak makna cepat.
enum BreakdownPhase {
  /// Nunggu token pertama.
  waiting,

  /// Lagi nulis; bagian yang penandanya udah masuk langsung punya rentang.
  writing,

  /// Lengkap, valid, udah di-cache.
  done,

  /// 15 detik tanpa token. Request tetep jalan.
  slow,

  /// Putus / mandek di tengah; yang udah masuk tetep ada.
  cut,

  /// Gagal sebelum ada token, atau jawaban gak valid dua kali.
  failed,
}

/// Hasil Bedahin satu grup (docs/llm.md, Bedahin).
class Breakdown {
  const Breakdown({
    this.sections = const [],
    this.terms = const [],
    this.links = const [],
    this.practice,
  });

  /// 1–6 bagian per langkah argumen, rentangnya urut nutup `K1..Kn`.
  final List<BreakdownSection> sections;

  /// Tokoh & istilah. Kosong = blok gak tampil.
  final List<BreakdownTerm> terms;

  /// Nyambung ke. Kosong = blok gak tampil.
  final List<BreakdownLink> links;

  /// Praktekinnya gini. Null = blok gak tampil.
  final String? practice;
}

/// Satu langkah argumen: kalimat terjemahan `K[from]..K[to]` (mulai 1,
/// nomornya nyambung lintas paragraf grup).
class BreakdownSection {
  const BreakdownSection({
    required this.from,
    required this.to,
    this.title = '',
    this.meaning = '',
    this.logic = '',
  });

  final int from;
  final int to;

  /// Ditampilin cuma kalau bagiannya ≥ 2.
  final String title;
  final String meaning;
  final String logic;
}

class BreakdownTerm {
  const BreakdownTerm({
    required this.label,
    this.exact,
    required this.explanation,
    this.sentence,
  });

  final String label;

  /// Kata persis di terjemahan, buat sorotan. Null = gak ketemu: istilahnya
  /// tetep tampil, tanpa sorot.
  final String? exact;
  final String explanation;

  /// Kalimat (`K`, mulai 1) pertama yang memuat [exact].
  final int? sentence;
}

class BreakdownLink {
  const BreakdownLink({this.chapter, required this.title, required this.why});

  /// Nomor bab di DAFTAR BAB (`B<n>`, mulai 1, urut `sortOrder`). Null =
  /// lanjutan: grup berikutnya di bab yang sama.
  final int? chapter;
  final String title;
  final String why;
}

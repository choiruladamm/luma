import '../../../../data/repositories/chat_context_repository.dart';
import '../view_models/chat_view_model.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book_chat.dart';

extension ChatPhaseCopy on ChatPhase {
  String get label => switch (this) {
    ChatPhase.preparing => 'Bentar, lagi siapin obrolan…',
    ChatPhase.retrieving => 'Lagi nyari sumber di buku…',
    ChatPhase.waiting => 'Bentar, lagi mikir…',
    ChatPhase.writing => 'Lagi nulis…',
    ChatPhase.slow => 'Agak lama nih, masih diproses…',
    ChatPhase.done => 'Jawaban selesai',
    ChatPhase.failed => 'Yah, gagal nih',
    ChatPhase.cut => 'Jawabannya keputus.',
    ChatPhase.stopped => 'Dihentiin.',
    ChatPhase.interrupted => 'Obrolan sempat terputus',
  };
}

extension ChatPhaseKind on ChatPhase {
  /// Gagal beneran (bukan dihentiin user): dapet ikon pink di atas label.
  bool get isFailure => switch (this) {
    ChatPhase.failed || ChatPhase.cut || ChatPhase.interrupted => true,
    _ => false,
  };
}

extension ChatLaunchCopy on ChatLaunchOrigin {
  String get backLabel => switch (this) {
    ChatLaunchOrigin.meaning => 'Balik ke Terjemahin',
    ChatLaunchOrigin.breakdown => 'Kembali',
    ChatLaunchOrigin.reader => 'Balik baca',
  };
}

extension ChatErrorCopy on AiException {
  bool get needsSettings =>
      error == AiError.noApiKey ||
      (error == AiError.http && [401, 402, 403].contains(status));
  String get chatMessage {
    if (error == AiError.noApiKey) {
      return 'API key belum diisi. Isi dulu di Pengaturan, lalu kirim lagi.';
    }
    if (error == AiError.network) {
      return 'Koneksi lagi putus. Cek internet lo, lalu coba lagi.';
    }
    if (error == AiError.timeout) {
      return 'Kelamaan nunggu jawaban. Lo bisa coba lagi.';
    }
    if (error == AiError.invalidResponse) {
      return 'Jawabannya belum lolos pengecekan. Coba lagi, yuk.';
    }
    if (status == 401 || status == 403) {
      return 'API key ditolak. Periksa key lo di Pengaturan.';
    }
    if (status == 402) {
      return 'Saldo OpenRouter habis. Cek akun lo, lalu coba lagi.';
    }
    if (status == 429) {
      return 'Lagi kena batas request. Tunggu sebentar, lalu coba lagi.';
    }
    return 'Layanan AI lagi bermasalah. Coba lagi nanti.';
  }
}

String chatTimeGroup(DateTime at, DateTime now) {
  final local = at.toLocal(), today = now.toLocal();
  final date = DateTime(local.year, local.month, local.day);
  final start = DateTime(today.year, today.month, today.day);
  if (date == start) return 'Hari ini';
  if (date == DateTime(start.year, start.month, start.day - 1)) {
    return 'Kemarin';
  }
  if (date.isAfter(start.subtract(const Duration(days: 7)))) {
    return '7 hari terakhir';
  }
  return 'Lebih lama';
}

extension ChatIndexCopy on ChatState {
  String? get indexLabel {
    final examined = explorationProgress;
    if ((phase == ChatPhase.retrieving || phase == ChatPhase.slow) &&
        examined != null) {
      final where = examined.label == null
          ? 'Lagi meriksa isi buku…'
          : 'Lagi baca ${examined.label}…';
      return '$where ${examined.completed}/${examined.total} potongan';
    }
    final progress = indexProgress;
    if ((phase != ChatPhase.retrieving && phase != ChatPhase.slow) ||
        progress == null ||
        progress.completed >= progress.total) {
      return null;
    }
    return 'Lagi nyiapin buku… ${progress.completed}/${progress.total} potongan';
  }
}

extension ChatDraftCopy on ChatTurn {
  String draftLabel(ChatPhase phase) {
    if (error == AiError.invalidResponse && !phase.isRunning) {
      return 'Draf ini belum lolos pengecekan jawaban.';
    }
    return phase.label;
  }
}

extension ChatStatusCopy on ChatState {
  /// Label status di bawah jawaban yang sedang berjalan/berhenti.
  String statusLabel(ChatPhase phase) {
    if (repairAttempt > 0 && phase.isRunning) {
      return 'Lagi benerin format jawaban… ($repairAttempt/$chatMaxRepairs)';
    }
    return turns.lastOrNull?.draftLabel(phase) ?? phase.label;
  }
}

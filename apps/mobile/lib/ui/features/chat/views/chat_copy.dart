import 'package:luma/l10n/l10n.dart';

import '../../../../data/repositories/chat_context_repository.dart';
import '../view_models/chat_view_model.dart';
import '../../../../domain/chat_steps.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book_chat.dart';

extension ChatPhaseCopy on ChatPhase {
  String label(AppLocalizations l10n) => switch (this) {
    ChatPhase.preparing => l10n.chatHangOnPreparingTheChat,
    ChatPhase.retrieving => l10n.chatLookingForSourcesInTheBook,
    ChatPhase.waiting => l10n.chatHangOnThinking,
    ChatPhase.writing => l10n.chatWriting,
    ChatPhase.slow => l10n.chatTakingAWhileStillWorking,
    ChatPhase.done => l10n.chatResponseComplete,
    ChatPhase.failed => l10n.meaningSomethingWentWrong,
    ChatPhase.cut => l10n.chatTheResponseWasCutOff,
    ChatPhase.stopped => l10n.chatStopped,
    ChatPhase.interrupted => l10n.chatTheChatWasInterrupted,
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
  String backLabel(AppLocalizations l10n) => switch (this) {
    ChatLaunchOrigin.meaning => l10n.chatBackToTranslation,
    ChatLaunchOrigin.breakdown => l10n.chatBack,
    ChatLaunchOrigin.reader => l10n.chatBackToReading,
  };
}

extension ChatErrorCopy on AiException {
  bool get needsSettings =>
      error == AiError.noApiKey ||
      (error == AiError.http && [401, 402, 403].contains(status));
  String chatMessage(AppLocalizations l10n) {
    if (error == AiError.noApiKey) {
      return l10n.chatNoApiKeyYetAddIt;
    }
    if (error == AiError.network) {
      return l10n.chatConnectionLostCheckYourInternetAnd;
    }
    if (error == AiError.timeout) {
      return l10n.chatTheResponseTookTooLongYou;
    }
    if (error == AiError.invalidResponse) {
      return l10n.chatTheResponseHasnTPassedValidation;
    }
    if (status == 401 || status == 403) {
      return l10n.chatApiKeyRejectedCheckYourKey;
    }
    if (status == 402) {
      return l10n.chatYourOpenrouterCreditHasRunOut;
    }
    if (status == 429) {
      return l10n.chatRateLimitReachedWaitAMoment;
    }
    return l10n.chatTheAiServiceIsHavingTrouble;
  }
}

String chatTimeGroup(AppLocalizations l10n, DateTime at, DateTime now) {
  final local = at.toLocal(), today = now.toLocal();
  final date = DateTime(local.year, local.month, local.day);
  final start = DateTime(today.year, today.month, today.day);
  if (date == start) return l10n.chatToday;
  if (date == DateTime(start.year, start.month, start.day - 1)) {
    return l10n.chatYesterday;
  }
  if (date.isAfter(start.subtract(const Duration(days: 7)))) {
    return l10n.chatLastDays;
  }
  return l10n.chatOlder;
}

extension ChatIndexCopy on ChatState {
  String? indexLabel(AppLocalizations l10n) {
    final examined = explorationProgress;
    if ((phase == ChatPhase.retrieving || phase == ChatPhase.slow) &&
        examined != null) {
      final where = examined.label == null
          ? l10n.chatCheckingTheBook
          : l10n.chatReading(examined.label!);
      return l10n.chatChunks(where, examined.completed, examined.total);
    }
    final progress = indexProgress;
    if ((phase != ChatPhase.retrieving && phase != ChatPhase.slow) ||
        progress == null ||
        progress.completed >= progress.total) {
      return null;
    }
    return l10n.chatPreparingTheBookChunks(progress.completed, progress.total);
  }
}

extension ChatStepCopy on ChatStep {
  /// Teks baris status saat langkah ini yang lagi jalan ("Lagi baca Book II › IV").
  String statusLabel(AppLocalizations l10n) => switch (kind) {
    ChatStepKind.plan => l10n.chatPlanning,
    ChatStepKind.cache => l10n.chatLoadingSavedNotes,
    ChatStepKind.answer => l10n.chatWritingTheResponse,
    ChatStepKind.read ||
    ChatStepKind.search ||
    ChatStepKind.repair ||
    ChatStepKind.retry => l10n.chatWorking(
      label[0].toLowerCase(),
      label.substring(1),
    ),
    ChatStepKind.skip || ChatStepKind.stop => label,
  };
}

extension ChatDraftCopy on ChatTurn {
  String draftLabel(AppLocalizations l10n, ChatPhase phase) {
    if (error == AiError.invalidResponse && !phase.isRunning) {
      return l10n.chatThisDraftHasnTPassedResponse;
    }
    return phase.label(l10n);
  }
}

extension ChatStatusCopy on ChatState {
  /// Label status di bawah jawaban yang sedang berjalan/berhenti.
  String statusLabel(AppLocalizations l10n, ChatPhase phase) {
    if (repairAttempt > 0 && phase.isRunning) {
      return l10n.chatFixingTheResponseFormat(repairAttempt, chatMaxRepairs);
    }
    return turns.lastOrNull?.draftLabel(l10n, phase) ?? phase.label(l10n);
  }
}

extension ChatProblemCopy on ChatProblem {
  String label(AppLocalizations l10n) => switch (this) {
    ChatProblem.bookDeleted => l10n.bookDeleted,
    ChatProblem.bookChanged => l10n.bookChanged,
    ChatProblem.historyDamaged => l10n.chatHistoryDamaged,
    ChatProblem.unavailable => l10n.chatUnavailable,
    ChatProblem.invalidQuestion => l10n.questionInvalid,
    ChatProblem.invalidCheckpoint => l10n.checkpointInvalid,
  };
}

extension ChatAnswerDisplayCopy on ChatAnswer {
  String displayNote(AppLocalizations l10n) {
    if (formatVersion == 2) return '';
    return switch (status) {
      ChatAnswerStatus.partial => l10n.chatPartialNote,
      ChatAnswerStatus.notFound => l10n.chatNoEvidenceNote,
      _ => '',
    };
  }
}

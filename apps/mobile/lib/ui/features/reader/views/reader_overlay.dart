import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../domain/models/book.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/search_navigator.dart';
import 'reader_capsule.dart';
import 'reader_overlays.dart';
import 'reader_types.dart';

/// Lapisan di atas teks bab: scrim sheet, kapsul atas/bawah, navigator Cari
/// kata, hint Ngobrol, banner ngintip sumber, garis progres. Dengerin
/// [fraction] sendiri biar scroll gak rebuild halaman.
class ReaderOverlay extends StatelessWidget {
  const ReaderOverlay({
    super.key,
    required this.book,
    required this.chapter,
    required this.fraction,
    required this.chrome,
    required this.prefs,
    required this.sheetOpen,
    required this.lastSheet,
    required this.search,
    required this.scrolling,
    required this.chatReady,
    required this.chatHintVisible,
    required this.visitLabel,
    required this.isVisit,
    required this.onBack,
    required this.onToc,
    required this.onMore,
    required this.onChat,
    required this.onStepSearch,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onContinueReading,
  });

  final ReaderBook book;
  final ChapterInfo chapter;
  final ValueListenable<double> fraction;
  final ReaderChrome chrome;
  final ReaderPrefs prefs;

  /// Sheet dari kapsul lagi kebuka; [lastSheet] nentuin warna scrim, termasuk
  /// pas lagi fade out.
  final bool sheetOpen;
  final ReaderSheet lastSheet;
  final SearchMode? search;
  final ValueListenable<bool> scrolling;
  final bool chatReady;
  final bool chatHintVisible;

  /// Lagi ngintip sumber dari obrolan: kapsul diganti banner + aksi.
  final bool isVisit;
  final String visitLabel;
  final VoidCallback onBack;
  final VoidCallback onToc;
  final VoidCallback onMore;
  final VoidCallback onChat;
  final void Function(int delta) onStepSearch;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final VoidCallback? onContinueReading;

  @override
  Widget build(BuildContext context) {
    final b = book, ch = chapter;
    return ValueListenableBuilder(
      valueListenable: fraction,
      builder: (context, f, _) {
        final progress = bookProgress(
          charOffset: ch.charOffset,
          chapterChars: ch.chars,
          fraction: f,
          totalChars: b.totalChars,
        );
        final left = ((1 - f) * ch.chars).round();
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: sheetOpen ? 1 : 0,
                  duration: sheetOpen ? Motion.sheetOpen : Motion.sheetClose,
                  child: ColoredBox(
                    // Aa: tipis, teks tetep keliatan buat preview setelan.
                    color:
                        lastSheet == ReaderSheet.aa ||
                            lastSheet == ReaderSheet.menu
                        ? context.stabilo.scrimSoft
                        : context.stabilo.scrim,
                  ),
                ),
              ),
            ),
            if (!isVisit)
              Positioned.fill(
                child: ReaderCapsules(
                  chrome: chrome,
                  top: ReaderTopCapsule(
                    title: b.title,
                    subtitle: ch.title,
                    onBack: onBack,
                    onToc: onToc,
                    onMore: onMore,
                    searchActive: search != null,
                    tocOpen: sheetOpen && lastSheet == ReaderSheet.toc,
                    moreOpen:
                        sheetOpen &&
                        (lastSheet == ReaderSheet.menu ||
                            lastSheet == ReaderSheet.aa),
                  ),
                  bottom: search != null
                      ? null
                      : ReaderChatDock(
                          progress: progress,
                          onChat: chatReady ? onChat : null,
                          label: f >= 0.999
                              ? '${ch.title} kelar'
                              : '±${readingMinutes(left)} mnt lagi',
                        ),
                ),
              ),
            // Mode cari: navigator hasil gantiin pill progres, gak ikut
            // ngumpet bareng kapsul.
            if (search case final mode? when !isVisit)
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset + capsuleBottomGap,
                child: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: scrolling,
                    builder: (context, compact, _) => SearchNavigator(
                      word: mode.raw,
                      position: mode.index + 1,
                      total: mode.hits.length,
                      truncated: mode.truncated,
                      chapterTitle: mode.hits[mode.index].chapter,
                      compact: compact,
                      onPrevious: mode.index > 0
                          ? () => onStepSearch(-1)
                          : null,
                      onNext: mode.index + 1 < mode.hits.length
                          ? () => onStepSearch(1)
                          : null,
                      onList: onOpenSearch,
                      onClose: onCloseSearch,
                    ),
                  ),
                ),
              ),
            if (chatHintVisible && !isVisit && !sheetOpen)
              Positioned(
                right: Layout.margin,
                bottom: bottomInset + 70,
                child: const ChatHintBubble(),
              ),
            if (isVisit)
              Positioned(
                left: Space.s4,
                right: Space.s4,
                top: MediaQuery.paddingOf(context).top + 7,
                child: SourceVisitBanner(label: visitLabel),
              ),
            if (isVisit)
              Positioned(
                left: Space.s4,
                right: Space.s4,
                bottom: bottomInset + Space.s3,
                child: SourceVisitActions(
                  onBack: onBack,
                  onContinue: onContinueReading,
                ),
              ),
            if (prefs.showProgressLine) ReaderProgressLine(progress: progress),
          ],
        );
      },
    );
  }
}

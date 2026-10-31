import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/chat_repository.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/edge_fade.dart';

final chatSourceProvider = StreamProvider.autoDispose
    .family<ChatSourceLocation?, ChatSourceRef>(
      (ref, request) => ref.watch(chatRepositoryProvider).watchSource(request),
    );

Future<bool?> showChatSourceSheet(
  BuildContext context, {
  required ChatSourceRef request,
  required ChatSource snapshot,
}) => showAppSheet<bool>(
  context,
  maxHeight: Layout.chatSheetHeight,
  builder: (_) => ChatSourceSheet(request: request, snapshot: snapshot),
);

class ChatSourceSheet extends ConsumerWidget {
  const ChatSourceSheet({
    super.key,
    required this.request,
    required this.snapshot,
  });
  final ChatSourceRef request;
  final ChatSource snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatSourceProvider(request));
    final location = state.asData?.value;
    final source = location?.source ?? snapshot;
    final available = location?.available ?? false;
    final pad = Layout.sheetPadding;
    // Kutipan + konteks ikut Aa, termasuk margin kiri-kanan persis Aa.
    final typo = ReaderTypography(
      ref.watch(readerPrefsProvider).value ?? const ReaderPrefs(),
      Theme.of(context).brightness,
    );
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: EdgeFadeScroll(
              top: const EdgeFadeSide(20, clear: Layout.artinyaGrabberZone),
              bottom: const EdgeFadeSide(
                20,
                clear: Layout.artinyaActions - Space.s4,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  typo.margin,
                  30,
                  typo.margin,
                  Layout.artinyaActions,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Space.s2,
                      runSpacing: Space.s2,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: context.stabilo.accent,
                            borderRadius: BorderRadius.circular(Radii.full),
                          ),
                          child: Text(
                            '${source.chapterTitle} · ${source.anchors.map((a) => 'bagian ${a.paragraphIndex + 1}').join(' · ')}',
                            style: StabiloType.caption.copyWith(
                              fontSize: 13,
                              height: 16 / 13,
                              fontWeight: FontWeight.w700,
                              color: context.stabilo.onAccent,
                            ),
                          ),
                        ),
                        if (location?.positionLabel != null)
                          Text(
                            location!.positionLabel!,
                            style: StabiloType.caption.copyWith(
                              color: context.stabilo.ink2,
                            ),
                          ),
                      ],
                    ),
                    if (location?.before != null)
                      SelectableText(
                        location!.before!,
                        style: typo.style.copyWith(color: context.stabilo.ink2),
                      ),
                    Stack(
                      key: const ValueKey('source-quote'),
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -12,
                          right: -12,
                          top: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.stabilo.muted,
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: SelectableText(source.text, style: typo.style),
                        ),
                      ],
                    ),
                    if (location?.after != null)
                      SelectableText(
                        location!.after!,
                        style: typo.style.copyWith(color: context.stabilo.ink2),
                      ),
                    if (state.isLoading || !available)
                      Text(state.sourceMessage, style: StabiloType.caption),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: pad.top,
            left: 0,
            right: 0,
            child: const SheetGrabber(),
          ),
          Positioned(
            left: Space.s4,
            right: Space.s4,
            bottom: pad.bottom,
            child: Row(
              spacing: 10,
              children: [
                CircleButton(
                  semanticLabel: 'Tutup',
                  icon: AppIcons.close,
                  size: Layout.chatComposer,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: !state.isLoading && !available
                      ? Container(
                          height: Layout.chatComposer,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.stabilo.muted,
                            borderRadius: BorderRadius.circular(Radii.full),
                          ),
                          child: Text(
                            'Bukunya udah berubah',
                            style: StabiloType.label.copyWith(
                              color: context.stabilo.ink3,
                            ),
                          ),
                        )
                      : AppButton.primary(
                          label: 'Buka di buku',
                          icon: AppIcons.book,
                          onPressed: available
                              ? () => Navigator.of(context).pop(true)
                              : null,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on AsyncValue<ChatSourceLocation?> {
  String get sourceMessage {
    if (isLoading) return 'Lagi ngecek lokasi kutipan…';
    if (asData?.value?.available == true) {
      return 'Cek teks aslinya tanpa mengubah posisi baca lo.';
    }
    return 'Sumber ini udah gak tersedia atau jawabannya belum lolos pengecekan. Kutipan lama tetap bisa lo baca.';
  }
}

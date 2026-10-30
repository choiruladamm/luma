import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/chat_repository.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_type.dart';
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
                  pad.left,
                  Space.s6,
                  pad.right,
                  Layout.artinyaActions,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s2,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            source.chapterTitle,
                            style: StabiloType.caption,
                          ),
                        ),
                        CircleButton(
                          semanticLabel: 'Tutup',
                          icon: AppIcons.close,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    Text(
                      source.anchors
                          .map((a) => 'Paragraf ${a.paragraphIndex + 1}')
                          .join(' · '),
                      style: StabiloType.caption,
                    ),
                    SelectableText(
                      source.text,
                      style: StabiloType.forBrightness(
                        StabiloType.reading,
                        Theme.of(context).brightness,
                      ),
                    ),
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
            left: pad.left,
            right: pad.right,
            bottom: pad.bottom,
            child: AppButton.primary(
              label: 'Buka di buku',
              onPressed: available
                  ? () => Navigator.of(context).pop(true)
                  : null,
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

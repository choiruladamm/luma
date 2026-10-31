import 'package:flutter/material.dart';

import '../../../../domain/chat_markup.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/tag.dart';
import 'chat_response.dart';

/// Badan jawaban AI: paragraf, butir bernomor / bullet, kutipan buku, kartu
/// catatan, dan label asal paragraf (Tafsiran / Di luar buku). Font, ukuran,
/// dan jarak baris ikut Aa lewat [typo].
class ChatAnswerBlocks extends StatelessWidget {
  const ChatAnswerBlocks({
    super.key,
    required this.blocks,
    required this.typo,
    required this.running,
    required this.chip,
    required this.anchor,
  });

  /// Blok yang lagi keliatan; yang teksnya kosong dilewati.
  final List<ChatAnswerBlock> blocks;
  final ReaderTypography typo;

  /// Lagi streaming: kursor kedip di ujung blok terakhir.
  final bool running;
  final Widget Function(ChatSource source) chip;

  /// Penanda posisi scroll per blok ([index] = urutan di [blocks]).
  final Widget Function(int index, Widget child) anchor;

  @override
  Widget build(BuildContext context) {
    final last = blocks.lastIndexWhere((b) => b.text.isNotEmpty);
    final children = <Widget>[];
    ChatAnswerBlock? previous;
    var number = 0;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.text.isEmpty) continue;
      final sameList =
          previous != null &&
          previous.layout == block.layout &&
          (block.layout == ChatAnswerLayout.item ||
              block.layout == ChatAnswerLayout.bullet);
      number = block.layout == ChatAnswerLayout.item
          ? (sameList ? number + 1 : 1)
          : 0;
      final label = _label(block, previous);
      if (children.isNotEmpty) {
        // Butir sedaftar lebih rapat dari jarak antar paragraf.
        children.add(
          SizedBox(
            height: sameList ? typo.paragraphGap / 2 : typo.paragraphGap,
          ),
        );
      }
      if (label != null) {
        children.add(label);
        children.add(const SizedBox(height: Space.s2));
      }
      children.add(
        anchor(
          i + 1,
          _block(context, block, number: number, caret: running && i == last),
        ),
      );
      previous = block;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Label kecil di awal grup paragraf tafsiran / pengetahuan luar.
  Widget? _label(ChatAnswerBlock block, ChatAnswerBlock? previous) {
    if (previous?.kind == block.kind) return null;
    return switch (block.kind) {
      ChatAnswerKind.interpretation => const Align(
        alignment: Alignment.centerLeft,
        child: Tag.section('Tafsiran', tone: TagTone.pink),
      ),
      ChatAnswerKind.external => const Align(
        alignment: Alignment.centerLeft,
        child: Tag.section('Di luar buku', tone: TagTone.muted),
      ),
      _ => null,
    };
  }

  Widget _block(
    BuildContext context,
    ChatAnswerBlock block, {
    required int number,
    required bool caret,
  }) {
    final c = context.stabilo;
    final text = _text(block, caret: caret);
    final line = typo.style.fontSize! * typo.style.height!;
    if (block.kind == ChatAnswerKind.conversation &&
        block.layout == ChatAnswerLayout.paragraph) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            SizedBox(
              height: line,
              child: Center(child: AppIcon(AppIcons.info, color: c.ink2)),
            ),
            Expanded(child: text),
          ],
        ),
      );
    }
    return switch (block.layout) {
      ChatAnswerLayout.paragraph => text,
      ChatAnswerLayout.item => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          SizedBox(
            width: typo.style.fontSize,
            child: Text(
              '$number',
              style: StabiloType.titleXs.copyWith(
                fontSize: 15,
                height: line / 15,
                color: c.ink,
              ),
            ),
          ),
          Expanded(child: text),
        ],
      ),
      ChatAnswerLayout.bullet => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          SizedBox(
            width: typo.style.fontSize,
            height: line,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.ink2,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: text),
        ],
      ),
      ChatAnswerLayout.quote => ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: c.accent),
              Expanded(
                child: Container(
                  color: c.muted,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: text,
                ),
              ),
            ],
          ),
        ),
      ),
    };
  }

  Widget _text(ChatAnswerBlock block, {required bool caret}) {
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final span in parseChatMarkup(block.text))
            TextSpan(
              text: span.text,
              style: TextStyle(
                fontWeight: span.bold ? FontWeight.w700 : null,
                fontStyle: span.italic ? FontStyle.italic : null,
              ),
            ),
          for (final source in block.sources)
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: chip(source),
            ),
          if (caret)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ChatCaret(),
            ),
        ],
      ),
      style: typo.style,
    );
  }
}

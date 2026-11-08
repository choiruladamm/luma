import 'package:luma/l10n/l10n.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';

/// Gelembung hint sekali tampil di atas tombol Ngobrol.
class ChatHintBubble extends StatelessWidget {
  const ChatHintBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s2,
            ),
            decoration: BoxDecoration(
              color: context.stabilo.toastBg,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              context.l10n.readerChatAboutTheBook,
              style: StabiloType.caption.copyWith(
                color: context.stabilo.toastInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: 61,
            bottom: -5,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 10,
                height: 10,
                color: context.stabilo.toastBg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill di atas layar pas ngintip sumber dari obrolan ("Lagi ngintip · ...").
class SourceVisitBanner extends StatelessWidget {
  const SourceVisitBanner({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, Space.s2, 14, Space.s2),
        decoration: BoxDecoration(
          color: context.stabilo.muted,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 7,
          children: [
            AppIcon(AppIcons.show, size: 16, color: context.stabilo.ink2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.caption.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.stabilo.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kapsul bawah pas ngintip sumber: balik ke obrolan / lanjut baca.
class SourceVisitActions extends StatelessWidget {
  const SourceVisitActions({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: context.stabilo.sheet,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(
          color: context.stabilo.capsuleLine,
          width: Layout.outline,
        ),
        boxShadow: Elevation.capsule(
          context.stabilo,
          Theme.of(context).brightness,
        ),
      ),
      child: Row(
        spacing: Space.s2,
        children: [
          Expanded(
            child: AppButton.secondary(
              label: context.l10n.readerBackToChat,
              icon: AppIcons.back,
              height: 48,
              onPressed: onBack,
            ),
          ),
          Expanded(
            child: AppButton.primary(
              label: context.l10n.readerKeepReading,
              icon: AppIcons.check,
              height: 48,
              onPressed: onContinue,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/file_storage.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/field.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/switch.dart';
import '../../../core/widgets/tag.dart';
import '../../../core/widgets/toast.dart';
import '../view_models/book_edit_view_model.dart';

/// Boards 33–38 Ubah judul & penulis: sheet bertumpuk di atas Info buku.
class BookEditSheet extends ConsumerStatefulWidget {
  const BookEditSheet({super.key, required this.bookId});

  final int bookId;

  @override
  ConsumerState<BookEditSheet> createState() => _BookEditSheetState();
}

class _BookEditSheetState extends ConsumerState<BookEditSheet> {
  late final _title = TextEditingController(
    text: ref.read(bookEditProvider(widget.bookId)).title,
  );
  late final _author = TextEditingController(
    text: ref.read(bookEditProvider(widget.bookId)).author,
  );

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final vm = ref.read(bookEditProvider(widget.bookId).notifier);
    final nav = Navigator.of(context);
    final ok = await vm.save();
    if (!mounted) return;
    // Sheet ini numpuk di atas sheet Info buku: snackbar bakal ketutup sheet,
    // jadi toast-nya di overlay root.
    if (ok) {
      final message = context.l10n.bookTitleAuthorUpdated;
      showOverlayToast(context, message);
      nav.pop();
    } else {
      showOverlayToast(context, context.l10n.bookCouldnTSave);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final id = widget.bookId;
    final s = ref.watch(bookEditProvider(id));
    final vm = ref.read(bookEditProvider(id).notifier);
    final epub = s.epubCoverName;
    final showEpub = epub != null && !s.useDefaultCover;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SheetFrame(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleButton(
                semanticLabel: context.l10n.dialogCancel,
                icon: AppIcons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
              Semantics(
                header: true,
                child: Text(
                  context.l10n.bookEditTitleAuthor,
                  style: StabiloType.titleXs,
                ),
              ),
              CircleButton(
                semanticLabel: context.l10n.chatSave,
                icon: AppIcons.check,
                primary: s.canSave,
                onPressed: s.canSave ? _save : null,
              ),
            ],
          ),
          Center(
            child: Column(
              spacing: Space.s2,
              children: [
                BookCover(
                  title: s.title.trim(),
                  author: s.authorOrNull,
                  file: showEpub
                      ? ref.read(fileStorageProvider).cover(epub)
                      : null,
                  width: 132,
                ),
                if (epub == null)
                  Text(
                    context.l10n.bookCoverPreview,
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.ink2,
                    ),
                  )
                else
                  Tag.status(
                    showEpub
                        ? context.l10n.bookOriginalEpubCover
                        : context.l10n.bookDefaultCover,
                    icon: AppIcons.image,
                  ),
              ],
            ),
          ),
          AppField(
            label: context.l10n.bookTitle,
            hint: context.l10n.importBookTitle,
            controller: _title,
            mono: false,
            error: s.titleEmpty ? context.l10n.editTitleEmpty : null,
            onChanged: vm.setTitle,
          ),
          AppField(
            label: context.l10n.bookAuthorOptional,
            hint: context.l10n.bookAuthorName,
            controller: _author,
            mono: false,
            onChanged: vm.setAuthor,
          ),
          if (epub != null)
            Container(
              padding: const EdgeInsets.fromLTRB(
                Space.s3 + 2,
                Space.s3,
                Space.s3,
                Space.s3,
              ),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.menu),
              ),
              child: Column(
                spacing: Space.s3,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.s3,
                    children: [
                      AppIcon(AppIcons.image, size: 18, color: c.ink),
                      Expanded(
                        child: Text(
                          s.useDefaultCover
                              ? context.l10n.bookYourOriginalCoverIsSavedYou
                              : context.l10n.bookThisCoverComesFromTheEpub,
                          style: StabiloType.caption.copyWith(color: c.ink2),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.bookUseDefaultCover,
                        style: StabiloType.label,
                      ),
                      AppSwitch(
                        value: s.useDefaultCover,
                        onChanged: vm.setUseDefaultCover,
                        semanticLabel: context.l10n.bookUseDefaultCover,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (s.canRevert)
            Row(
              spacing: Space.s3,
              children: [
                AppButton.secondary(
                  label: context.l10n.bookRestoreOriginals,
                  icon: AppIcons.undo,
                  height: 40,
                  onPressed: () {
                    vm.revert();
                    final r = ref.read(bookEditProvider(id));
                    _title.text = r.title;
                    _author.text = r.author;
                  },
                ),
                Expanded(
                  child: Text(
                    context.l10n.bookFromEpub(
                      s.originalTitle ?? '',
                      s.originalAuthor ?? context.l10n.unknownAuthor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(color: c.ink2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

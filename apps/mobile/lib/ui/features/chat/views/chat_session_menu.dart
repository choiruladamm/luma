import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../../../domain/chat_prompt.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/field.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/chat_view_model.dart';

enum _SessionAction { rename, delete }

Future<void> showChatSessionMenu(
  BuildContext context,
  ChatViewModel vm,
  ChatState state, {
  ChatSession? target,
}) async {
  final session = target ?? state.activeSession;
  if (session == null) return;
  final action = await showAppSheet<_SessionAction>(
    context,
    builder: (sheet) {
      final readOnly =
          session.invalid ||
          state.book == null ||
          session.isArchived(state.book!);
      Widget action(
        String label,
        List<List<dynamic>> icon,
        VoidCallback? onTap, {
        bool destructive = false,
        String? hint,
      }) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.field),
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s2),
              child: Row(
                spacing: 14,
                children: [
                  AppIcon(
                    icon,
                    color: destructive
                        ? context.stabilo.danger
                        : context.stabilo.ink,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: StabiloType.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: destructive
                                ? context.stabilo.danger
                                : context.stabilo.ink,
                          ),
                        ),
                        if (hint != null)
                          Text(
                            hint,
                            style: StabiloType.caption.copyWith(
                              color: context.stabilo.ink2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          22,
          16,
          MediaQuery.paddingOf(sheet).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.stabilo.ink2,
                ),
              ),
            ),
            action(
              context.l10n.chatRename,
              AppIcons.edit,
              readOnly
                  ? null
                  : () => Navigator.pop(sheet, _SessionAction.rename),
              hint: readOnly
                  ? context.l10n.chatUnavailableForArchivedChats
                  : null,
            ),
            action(
              context.l10n.chatDeleteChat,
              AppIcons.delete,
              () => Navigator.pop(sheet, _SessionAction.delete),
              destructive: true,
            ),
          ],
        ),
      );
    },
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _SessionAction.rename:
      await showAppSheet<void>(
        context,
        maxHeight: 1,
        builder: (_) => _RenameSession(vm: vm, session: session),
      );
    case _SessionAction.delete:
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialog) => Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: Space.s8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    Text(
                      context.l10n.chatDeleteThisChat,
                      style: StabiloType.titleMd.copyWith(
                        fontSize: 20,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      context.l10n.chatWillBePermanentlyDeletedYourBook(
                        session.title,
                      ),
                      style: StabiloType.body.copyWith(
                        fontSize: 14.5,
                        height: 1.5,
                        color: context.stabilo.ink2,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        spacing: 10,
                        children: [
                          Expanded(
                            child: AppButton.secondary(
                              label: context.l10n.dialogCancel,
                              height: 48,
                              onPressed: () => Navigator.pop(dialog, false),
                            ),
                          ),
                          Expanded(
                            child: AppButton.danger(
                              label: context.l10n.bookClear,
                              height: 48,
                              onPressed: () => Navigator.pop(dialog, true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          false;
      if (confirmed && context.mounted) await vm.deleteSession(session.id);
  }
}

class _RenameSession extends StatefulWidget {
  const _RenameSession({required this.vm, required this.session});
  final ChatViewModel vm;
  final ChatSession session;
  @override
  State<_RenameSession> createState() => _RenameSessionState();
}

class _RenameSessionState extends State<_RenameSession> {
  late final _text = TextEditingController(text: widget.session.title);
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _validate(String value) {
    String? error;
    try {
      chatTitle(value);
    } on FormatException catch (e) {
      error = e.message;
    }
    setState(() => _error = error);
  }

  Future<void> _save() async {
    _validate(_text.text);
    if (_error != null || _saving) return;
    setState(() => _saving = true);
    final saved = await widget.vm.renameSession(
      widget.session,
      chatTitle(_text.text),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = context.l10n.chatCouldnTSaveTheTitleTry;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SheetFrame(
      title: context.l10n.chatRename,
      showClose: false,
      actions: [
        Expanded(
          child: AppButton.secondary(
            label: context.l10n.dialogCancel,
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ),
        Expanded(
          child: AppButton.primary(
            label: context.l10n.chatSave,
            loading: _saving,
            onPressed: _error == null && !_saving ? _save : null,
          ),
        ),
      ],
      children: [
        AppField(
          label: context.l10n.chatChatTitle,
          showLabel: false,
          controller: _text,
          mono: false,
          hint: context.l10n.chatChatTitle,
          error: _error,
          onChanged: _validate,
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
  );
}

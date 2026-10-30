import 'package:flutter/material.dart';

import '../../../../domain/chat_prompt.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/dialog.dart';
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
    builder: (sheet) => SheetFrame(
      title: 'Obrolan ini',
      children: [
        Text(session.title),
        if (session.invalid ||
            state.book == null ||
            session.isArchived(state.book!))
          const Text('Arsip cuma bisa dibaca. Judulnya gak bisa diubah.'),
        AppButton.secondary(
          label: 'Ubah judul',
          icon: AppIcons.edit,
          onPressed:
              session.invalid ||
                  state.book == null ||
                  session.isArchived(state.book!)
              ? null
              : () => Navigator.pop(sheet, _SessionAction.rename),
        ),
        AppButton.secondary(
          label: 'Hapus obrolan ini',
          destructive: true,
          icon: AppIcons.delete,
          onPressed: () => Navigator.pop(sheet, _SessionAction.delete),
        ),
      ],
    ),
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
      final confirmed = await showConfirmDialog(
        context,
        title: 'Hapus obrolan ini?',
        message:
            '“${session.title}”\n\nPertanyaan dan jawaban di sesi ini akan dihapus. Obrolan lain, buku, dan posisi baca tetap tersimpan.',
        confirmLabel: 'Hapus',
        icon: AppIcons.delete,
      );
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
        _error = 'Judul belum tersimpan. Coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SheetFrame(
      title: 'Ubah judul obrolan',
      children: [
        AppField(
          label: 'Judul',
          controller: _text,
          mono: false,
          helper: 'Maksimal $chatTitleCodePoints karakter',
          error: _error,
          onChanged: _validate,
          onSubmitted: (_) => _save(),
        ),
        AppButton.primary(
          label: 'Simpan judul',
          loading: _saving,
          onPressed: _error == null && !_saving ? _save : null,
        ),
        AppButton.secondary(
          label: 'Batal',
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        const SizedBox(height: Space.s2),
      ],
    ),
  );
}

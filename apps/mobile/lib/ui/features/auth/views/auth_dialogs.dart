import 'package:flutter/material.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/dialog.dart';

/// Board Akun 09: keluar. `true` = dikonfirmasi.
Future<bool> showSignOutDialog(BuildContext context) {
  final l = context.l10n;
  return showConfirmDialog(
    context,
    title: l.authSignOutTitle,
    message: l.authSignOutBody,
    confirmLabel: l.authSignOut,
    destructive: false,
  );
}

/// Kartu dialog akun: judul, isi, tombol bertumpuk (board Akun 10, 11).
class _AccountDialog extends StatelessWidget {
  const _AccountDialog({
    required this.title,
    required this.children,
    required this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Space.s6,
        vertical: Space.s6,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s3,
          children: [
            Text(title, style: StabiloType.titleMd.copyWith(color: c.ink)),
            ...children,
            const SizedBox(height: Space.s1),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Board Akun 10: akun Google beda dari akun terakhir di HP ini. Gak bisa
/// ditutup tanpa milih.
Future<void> showSwitchAccountDialog(
  BuildContext context, {
  required String from,
  required String to,
  required Future<void> Function() onConfirm,
  required Future<void> Function() onKeep,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (context) => _SwitchAccountDialog(
      from: from,
      to: to,
      onConfirm: onConfirm,
      onKeep: onKeep,
    ),
  );
}

class _SwitchAccountDialog extends StatefulWidget {
  const _SwitchAccountDialog({
    required this.from,
    required this.to,
    required this.onConfirm,
    required this.onKeep,
  });

  final String from;
  final String to;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onKeep;

  @override
  State<_SwitchAccountDialog> createState() => _SwitchAccountDialogState();
}

class _SwitchAccountDialogState extends State<_SwitchAccountDialog> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await action();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    return PopScope(
      canPop: false,
      child: _AccountDialog(
        title: l.authSwitchTitle,
        actions: [
          AppButton.danger(
            label: l.authSwitchConfirm,
            loading: _busy,
            onPressed: _busy ? null : () => _run(widget.onConfirm),
          ),
          AppButton.secondary(
            label: l.authSwitchKeep,
            onPressed: _busy ? null : () => _run(widget.onKeep),
          ),
        ],
        children: [
          _AccountRow(
            label: l.authSwitchOwner,
            email: widget.from,
            faded: true,
          ),
          _AccountRow(label: l.authSwitchNew, email: widget.to),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${l.authSwitchBodyLead} '),
                TextSpan(
                  text: l.authSwitchBodyBold,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: l.authSwitchBodyTail),
              ],
            ),
            style: StabiloType.body.copyWith(color: c.ink2),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.label,
    required this.email,
    this.faded = false,
  });

  final String label;
  final String email;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Opacity(
      opacity: faded ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: 10),
        decoration: BoxDecoration(
          color: faded ? c.muted : c.sheet,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: faded ? null : Border.all(color: c.ink, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(label, style: StabiloType.caption.copyWith(color: c.ink2)),
            Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: StabiloType.label.copyWith(
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Board Akun 11: hapus akun, wajib centang 3 hal. [onConfirm] balikin
/// `true` kalau akun beneran kehapus; hasil dialog = hasil itu.
Future<bool> showDeleteAccountDialog(
  BuildContext context, {
  required String email,
  required Future<bool> Function() onConfirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) =>
        _DeleteAccountDialog(email: email, onConfirm: onConfirm),
  );
  return ok ?? false;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.email, required this.onConfirm});

  final String email;
  final Future<bool> Function() onConfirm;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _checked = [false, false, false];
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    navigator.pop(await widget.onConfirm());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final items = [
      l.authDeleteCheckAccount(widget.email),
      l.authDeleteCheckBackup,
      l.authDeleteCheckSync,
    ];
    final all = _checked.every((v) => v);
    return PopScope(
      canPop: !_busy,
      child: _AccountDialog(
        title: l.authDeleteTitle,
        actions: [
          AppButton.danger(
            label: l.authDeleteConfirm,
            loading: _busy,
            onPressed: all && !_busy ? _confirm : null,
          ),
          AppButton.secondary(
            label: l.dialogCancel,
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
        children: [
          Text(
            l.authDeleteBody,
            style: StabiloType.body.copyWith(color: c.ink2),
          ),
          for (var i = 0; i < items.length; i++)
            CheckboxListTile(
              value: _checked[i],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _checked[i] = v ?? false),
              title: Text(
                items[i],
                style: StabiloType.body.copyWith(color: c.ink),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          Text(
            l.authDeleteNote,
            style: StabiloType.caption.copyWith(color: c.ink3),
          ),
        ],
      ),
    );
  }
}

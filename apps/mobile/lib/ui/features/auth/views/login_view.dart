import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/services/backend_client.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/luma_logo.dart';
import '../view_models/auth_view_model.dart';
import '../view_models/login_view_model.dart';
import 'auth_dialogs.dart';
import 'auth_toast.dart';

/// Build dev = email + kata sandi; rilis = Google (board Akun 05).
final devLoginProvider = Provider<bool>((ref) => appFlavor == 'dev');

/// Layar Masuk (board Akun 01–07). Login wajib: gak ada bottom bar dan gak
/// bisa dilewatin; sukses → router pindah sendiri ke Rak.
class LoginView extends ConsumerWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loginViewModelProvider);
    final vm = ref.read(loginViewModelProvider.notifier);
    ref.listen(loginViewModelProvider, (prev, next) {
      if (next.step == LoginStep.switchAccount &&
          prev?.step != LoginStep.switchAccount) {
        showSwitchAccountDialog(
          context,
          from: next.pendingSwitch?.previousEmail ?? '',
          to: next.pendingSwitch?.user.email ?? '',
          onConfirm: vm.confirmSwitch,
          onKeep: vm.keepOldAccount,
        );
      }
    });

    ref.listen(authControllerProvider, (prev, next) {
      final before = prev?.value?.status;
      final after = next.value;
      if (after?.status == AuthStatus.signedIn &&
          before != AuthStatus.signedIn &&
          after?.user != null) {
        showSignedInToast(context, after!.user!.name);
      }
    });

    final c = context.stabilo;
    final Widget body = switch (state.step) {
      LoginStep.invite => _InviteBody(state: state),
      LoginStep.start || LoginStep.switchAccount =>
        ref.watch(devLoginProvider)
            ? _DevBody(state: state)
            : _GoogleBody(state: state),
    };
    return PopScope(
      canPop: state.step == LoginStep.start,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) vm.backToStart();
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(child: body),
      ),
    );
  }
}

/// Halaman judul: logo, judul, subjudul miring, ornamen stabilo, tiga bab.
class _TitlePage extends StatelessWidget {
  const _TitlePage({this.faded = false, this.footnote = false});

  final bool faded;

  /// Angka ¹ merah di judul (board Akun 03, 04).
  final bool footnote;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    return AnimatedOpacity(
      opacity: faded ? 0.45 : 1,
      duration: Motion.highlight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 30,
        children: [
          Column(
            spacing: 10,
            children: [
              const LumaLogo(size: 52),
              Text.rich(
                TextSpan(
                  text: l.authLoginTitle,
                  children: [
                    if (footnote)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.top,
                        child: Text(
                          '1',
                          style: StabiloType.titleSm.copyWith(color: c.danger),
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: StabiloType.display.copyWith(
                  fontSize: 34,
                  height: 1.05,
                  color: c.ink,
                ),
              ),
              Text(
                l.authLoginSubtitle,
                textAlign: TextAlign.center,
                style: StabiloType.reading.copyWith(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: c.ink2,
                ),
              ),
              const _Ornament(),
            ],
          ),
          Column(
            spacing: 14,
            children: [
              _Chapter(
                l.authChapterOne,
                l.authBenefitQuota,
                l.authBenefitQuotaNote,
              ),
              _Rule(color: c.outline),
              _Chapter(
                l.authChapterTwo,
                l.authBenefitBackup,
                l.authBenefitBackupNote,
              ),
              _Rule(color: c.outline),
              _Chapter(
                l.authChapterThree,
                l.authBenefitSync,
                l.authBenefitSyncNote,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    Widget pill(double w, Color color) => Container(
      width: w,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [pill(22, c.accent), pill(6, c.ink), pill(22, c.accent)],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.color, this.width = 28});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) =>
      Container(width: width, height: 1.5, color: color);
}

class _Chapter extends StatelessWidget {
  const _Chapter(this.label, this.title, this.note);

  final String label;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Column(
      spacing: 2,
      children: [
        Text(
          label,
          style: StabiloType.reading.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 13 * 0.18,
            color: c.ink3,
          ),
        ),
        Text(
          title,
          textAlign: TextAlign.center,
          style: StabiloType.reading.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        Text(
          note,
          textAlign: TextAlign.center,
          style: StabiloType.reading.copyWith(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: c.ink2,
          ),
        ),
      ],
    );
  }
}

/// Catatan kaki gagal: garis pendek + ¹ + judul berstabilo pink + keterangan.
class _Footnote extends StatelessWidget {
  const _Footnote({required this.title, required this.body, this.label});

  final String title;
  final String body;

  /// "CATATAN" di atas (board Akun 07).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.s2,
        children: [
          _Rule(color: c.ink, width: 72),
          if (label != null)
            Text(
              label!,
              style: StabiloType.micro.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: c.ink3,
              ),
            ),
          Text.rich(
            TextSpan(
              children: [
                if (label == null)
                  TextSpan(
                    text: '1 ',
                    style: TextStyle(
                      color: c.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                TextSpan(
                  text: title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    background: Paint()..color = c.pinkSoft,
                  ),
                ),
                TextSpan(text: ' $body'),
              ],
            ),
            style: StabiloType.body.copyWith(
              fontSize: 13.5,
              height: 1.45,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  static const _sentinel = '\u0000';

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final parts = context.l10n.authPrivacyNote(_sentinel).split(_sentinel);
    final style = StabiloType.caption.copyWith(
      fontSize: 12.5,
      height: 1.4,
      color: c.ink2,
    );
    return Center(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: parts.first),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('${backendBaseUrl(appFlavor)}/privacy'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Semantics(
                  link: true,
                  child: Text(
                    context.l10n.authPrivacyPolicy,
                    style: style.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
            if (parts.length > 1) TextSpan(text: parts.last),
          ],
        ),
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

/// Tombol Google: putih bergaris dengan tanda G (aset resmi menyusul saat
/// OAuth client ID diisi, board Akun copy & aturan).
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: c.sheet,
          foregroundColor: c.ink,
          side: BorderSide(color: c.ink, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: StabiloType.label.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: Space.s3,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.sheet,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.outline, width: 1.5),
                ),
                child: Text(
                  'G',
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(
      strokeWidth: 3,
      color: context.stabilo.ink,
      backgroundColor: context.stabilo.outline,
    ),
  );
}

/// Board Akun 01–04: Google.
class _GoogleBody extends ConsumerWidget {
  const _GoogleBody({required this.state});

  final LoginState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final l = context.l10n;
    final vm = ref.read(loginViewModelProvider.notifier);
    final error = state.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s6, 0, Space.s6, Space.s8),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: _TitlePage(
                  faded: state.loading,
                  footnote: error != null,
                ),
              ),
            ),
          ),
          if (error == LoginError.network)
            _Footnote(title: l.authNetworkTitle, body: l.authNetworkBody)
          else if (error != null)
            _Footnote(title: l.authRejectedTitle, body: l.authRejectedBody),
          const SizedBox(height: Space.s6),
          if (state.loading) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: Space.s2,
              children: [
                const _Spinner(),
                Flexible(
                  child: Text(
                    l.authGoogleWillAsk,
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.ink2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s3),
            AppButton.secondary(
              label: l.authConnectingGoogle,
              onPressed: null,
              loading: true,
            ),
          ] else if (error == LoginError.network)
            AppButton.primary(label: l.authTryAgain, onPressed: vm.signInGoogle)
          else
            _GoogleButton(
              label: error == null
                  ? l.authSignInGoogle
                  : l.authUseAnotherAccount,
              onPressed: vm.signInGoogle,
            ),
          const SizedBox(height: Space.s3),
          const _PrivacyNote(),
        ],
      ),
    );
  }
}

/// Board Akun 05: build dev, "Isi yang kosong."
class _DevBody extends ConsumerStatefulWidget {
  const _DevBody({required this.state});

  final LoginState state;

  @override
  ConsumerState<_DevBody> createState() => _DevBodyState();
}

class _DevBodyState extends ConsumerState<_DevBody> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final state = widget.state;
    final vm = ref.read(loginViewModelProvider.notifier);
    final ready = _email.text.contains('@') && _password.text.isNotEmpty;
    final (title, body) = switch (state.error) {
      LoginError.invalidCredentials => (
        l.authInvalidCredentialsTitle,
        l.authInvalidCredentialsBody,
      ),
      LoginError.userExists => (l.authUserExistsTitle, l.authUserExistsBody),
      LoginError.passwordTooShort => (
        l.authPasswordShortTitle,
        l.authPasswordShortBody,
      ),
      LoginError.network => (l.authNetworkTitle, l.authNetworkBody),
      null => (null, null),
      _ => (l.authRejectedTitle, l.authRejectedBody),
    };
    final reading = StabiloType.reading.copyWith(
      fontSize: 22,
      height: 1.9,
      color: c.ink,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s6,
        Space.s4,
        Space.s6,
        Space.s8,
      ),
      children: [
        Row(
          children: [
            const LumaLogo(size: 30),
            const Spacer(),
            Text(
              l.authDevLabel.toUpperCase(),
              style: StabiloType.micro.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: c.ink3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(Radii.full),
            ),
            child: Text(
              l.authDevBadge,
              style: StabiloType.tag.copyWith(color: c.ink),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          l.authDevTitle,
          style: StabiloType.display.copyWith(fontSize: 30, color: c.ink),
        ),
        const SizedBox(height: 18),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: Space.s1,
          children: [
            Text(l.authDevEmailLead, style: reading),
            _Blank(
              controller: _email,
              label: l.authEmailLabel,
              width: 190,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
            ),
            Text(l.authDevPasswordLead, style: reading),
            _Blank(
              controller: _password,
              label: l.authPasswordLabel,
              width: 130,
              secret: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          l.authDevNote,
          style: StabiloType.caption.copyWith(fontSize: 12.5, color: c.ink3),
        ),
        if (title != null) ...[
          const SizedBox(height: Space.s6),
          _Footnote(title: title, body: body!),
        ],
        const SizedBox(height: Space.s6),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: AppButton.secondary(
                label: l.authSignUp,
                onPressed: ready && !state.loading
                    ? () => vm.signUpEmail(_email.text, _password.text)
                    : null,
              ),
            ),
            Expanded(
              child: AppButton.primary(
                label: l.authSignIn,
                loading: state.loading,
                onPressed: ready && !state.loading
                    ? () => vm.signInEmail(_email.text, _password.text)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Isian titik-titik di dalam kalimat (board Akun 05, 06).
class _Blank extends StatelessWidget {
  const _Blank({
    required this.controller,
    required this.label,
    required this.width,
    this.secret = false,
    this.keyboardType,
    this.onChanged,
    this.error = false,
    this.fontSize = 19,
    this.mono = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final bool secret;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool error;
  final double fontSize;
  final bool mono;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final line = error ? c.danger : c.ink;
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        obscureText: secret,
        autofocus: autofocus,
        keyboardType: keyboardType,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: mono
            ? TextCapitalization.characters
            : TextCapitalization.none,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: (mono ? StabiloType.mono : StabiloType.titleSm).copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: label,
          hintStyle: TextStyle(color: c.ink3, fontWeight: FontWeight.w500),
          semanticCounterText: label,
          contentPadding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: line, width: 2.5),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: line, width: 2.5),
          ),
        ),
      ),
    );
  }
}

/// Board Akun 06–07: kode undangan.
class _InviteBody extends ConsumerStatefulWidget {
  const _InviteBody({required this.state});

  final LoginState state;

  @override
  ConsumerState<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends ConsumerState<_InviteBody> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final state = widget.state;
    final vm = ref.read(loginViewModelProvider.notifier);
    final (title, body) = switch (state.error) {
      LoginError.inviteUsed => (l.authInviteUsedTitle, l.authInviteUsedBody),
      LoginError.inviteInvalid => (
        l.authInviteInvalidTitle,
        l.authInviteInvalidBody,
      ),
      LoginError.network => (l.authNetworkTitle, l.authNetworkBody),
      null => (null, null),
      _ => (l.authRejectedTitle, l.authRejectedBody),
    };
    final canSubmit =
        _code.text.trim().isNotEmpty && state.error == null && !state.loading;
    void submit() {
      if (canSubmit) vm.submitInvite(_code.text);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s6,
        Space.s4,
        Space.s6,
        Space.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              children: [
                if (state.email case final email?)
                  Row(
                    spacing: Space.s2,
                    children: [
                      Text(
                        l.authSignedInAs,
                        style: StabiloType.caption.copyWith(color: c.ink2),
                      ),
                      Flexible(
                        child: Text(
                          email,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: vm.backToStart,
                        child: Text(l.authChange),
                      ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: vm.backToStart,
                      child: Text(l.authChange),
                    ),
                  ),
                const SizedBox(height: Space.s6),
                Text(
                  l.authInviteIntro,
                  style: StabiloType.reading.copyWith(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: c.ink2,
                  ),
                ),
                const SizedBox(height: Space.s4),
                Text(
                  l.authInviteLead,
                  style: StabiloType.reading.copyWith(
                    fontSize: 22,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: Space.s2),
                _Blank(
                  controller: _code,
                  label: 'LUMA-XXXX',
                  width: double.infinity,
                  fontSize: 30,
                  mono: true,
                  autofocus: true,
                  error: state.error != null,
                  onChanged: (_) {
                    vm.editInvite();
                    setState(() {});
                  },
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: Space.s2),
                Text(
                  l.authInviteHint,
                  style: StabiloType.caption.copyWith(color: c.ink3),
                ),
                if (title != null) ...[
                  const SizedBox(height: Space.s6),
                  _Footnote(title: title, body: body!, label: l.authNoteLabel),
                ],
              ],
            ),
          ),
          AppButton.primary(
            label: l.authContinue,
            loading: state.loading,
            onPressed: canSubmit ? submit : null,
          ),
        ],
      ),
    );
  }
}

/// Toast "Udah masuk. Halo, …!" setelah login (board Akun 13).
void showSignedInToast(BuildContext context, String name) => showAuthToast(
  context,
  context.l10n.authToastSignedIn(name.split(' ').first),
  tone: AuthToastTone.success,
);

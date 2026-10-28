import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../view_models/chat_view_model.dart';
import 'chat_composer.dart';
import 'chat_copy.dart';
import 'chat_history.dart';
import 'chat_session_menu.dart';
import 'chat_sessions_view.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, required this.bookId, this.launch});
  final int bookId;
  final ChatLaunchContext? launch;
  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  bool _leaving = false;
  ChatViewModel get _vm =>
      ref.read(chatViewModelProvider(widget.bookId).notifier);
  @override
  void initState() {
    super.initState();
    if (widget.launch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_vm.launch(widget.launch!));
      });
    }
  }

  Future<void> _navigate(VoidCallback action) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _vm.stop();
    if (!mounted) return;
    action();
    if (mounted) setState(() => _leaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatViewModelProvider(widget.bookId));
    final title = chatBookTitle(ref, widget.bookId);
    final error = state.error;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Layout.margin,
            Space.s3,
            Layout.margin,
            Space.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s5,
            children: [
              Row(
                spacing: Space.s2,
                children: [
                  CircleButton(
                    semanticLabel: 'Kembali',
                    icon: AppIcons.back,
                    onPressed: _leaving
                        ? null
                        : () => _navigate(() {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go(Routes.home);
                            }
                          }),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.activeSession?.title ?? 'Obrolan baru',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.titleXs,
                        ),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.caption.copyWith(
                            color: context.stabilo.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CircleButton(
                    semanticLabel: 'Riwayat obrolan',
                    icon: AppIcons.history,
                    onPressed: _leaving
                        ? null
                        : () => _navigate(
                            () => context.push(
                              Routes.chatSessions(widget.bookId),
                            ),
                          ),
                  ),
                  if (state.activeSession != null)
                    CircleButton(
                      semanticLabel: 'Menu sesi',
                      icon: AppIcons.more,
                      onPressed: state.changingSession
                          ? null
                          : () => showChatSessionMenu(context, _vm, state),
                    ),
                ],
              ),
              Expanded(child: _body(state)),
              if (widget.launch != null &&
                  widget.launch!.origin != ChatLaunchOrigin.reader)
                AppButton.secondary(
                  label: 'Balik baca',
                  onPressed: () =>
                      _navigate(() => context.pop(ReaderReturn.reading)),
                ),
              if (state.archived)
                const Text(
                  'Isi buku berubah. Obrolan ini jadi arsip dan gak bisa dilanjutkan.',
                  style: StabiloType.caption,
                ),
              if (state.problem != null)
                Text(state.problem!, style: StabiloType.caption),
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(error.chatMessage, style: StabiloType.caption),
                ),
              if (error?.needsSettings ?? false)
                AppButton.secondary(
                  label: 'Buka Pengaturan',
                  onPressed: () =>
                      _navigate(() => context.push(Routes.settings)),
                ),
              if (state.canRetry)
                AppButton.secondary(
                  label: 'Coba lagi',
                  onPressed: () => unawaited(_vm.retry()),
                ),
              if (state.archived || state.activeSession?.invalid == true)
                AppButton.primary(
                  label: 'Obrolan baru',
                  onPressed: () => unawaited(_vm.newSession()),
                )
              else if (!state.readOnly)
                ChatComposer(
                  draft: state.draft,
                  quote: state.selectedQuote,
                  canSend: state.canSend,
                  running: state.phase?.isRunning ?? false,
                  enabled: !state.loading && !state.busy,
                  onChanged: _vm.setDraft,
                  onSend: () => unawaited(_vm.send()),
                  onStop: () => unawaited(_vm.stop()),
                  onRemoveQuote: _vm.removeQuote,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ChatState state) {
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (state.turns.isNotEmpty) {
      return ChatHistory(
        key: ValueKey(state.activeSession?.id),
        turns: state.turns,
        anchor: state.scrollAnchor,
        phase: state.phase,
        onAnchor: _vm.setScrollAnchor,
      );
    }
    if (state.book == null) {
      return const Center(child: Text('Buku ini gak tersedia.'));
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s4,
          children: [
            const Text('Lagi kepikiran apa?', style: StabiloType.titleLg),
            const Text(
              'Tanyain yang bikin lo penasaran. Jawabannya bisa lo cek langsung di bukunya.',
              style: StabiloType.body,
            ),
            for (final question in [
              'Apa gagasan utama buku ini?',
              'Jelasin bagian ini lebih sederhana',
              'Apa hubungan gagasan antar bab?',
            ])
              AppButton.secondary(
                label: question,
                onPressed: state.busy ? null : () => _vm.setDraft(question),
              ),
          ],
        ),
      ),
    );
  }
}

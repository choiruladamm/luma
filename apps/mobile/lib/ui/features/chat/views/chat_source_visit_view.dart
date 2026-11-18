import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../routing/router.dart';
import '../../../../data/repositories/chat_repository.dart';
import '../../../core/widgets/toast.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../reader/views/reader_view.dart';
import '../../../../data/repositories/reading_progress_repository.dart';
import '../view_models/chat_view_model.dart';
import 'chat_source_sheet.dart';

/// The resolver stays subscribed so deletes, restore and content changes revoke
/// the renderer instead of leaving a stale paragraph at the same index.
final chatQuoteSourceProvider = StreamProvider.autoDispose
    .family<ChatSourceLocation?, ChatQuote>(
      (ref, quote) => ref.watch(chatRepositoryProvider).watchQuote(quote),
    );

final _visitProgressProvider = FutureProvider.autoDispose
    .family<ReadingPosition?, int>(
      (ref, bookId) =>
          ref.watch(readingProgressRepositoryProvider).load(bookId),
    );

class ChatSourceVisitView extends ConsumerStatefulWidget {
  const ChatSourceVisitView({super.key, this.request, this.quote})
    : assert((request == null) != (quote == null));
  final ChatSourceRef? request;
  final ChatQuote? quote;

  @override
  ConsumerState<ChatSourceVisitView> createState() => _ChatSourceVisitState();
}

class _ChatSourceVisitState extends ConsumerState<ChatSourceVisitView> {
  ChatSourceLocation? _initial;
  bool _revoked = false;
  bool _saving = false;

  Future<void> _continue() async {
    if (_saving || _revoked) return;
    setState(() => _saving = true);
    try {
      final bookId =
          widget.request?.bookId ?? widget.quote!.anchors.first.book.bookId;
      await ref
          .read(chatRepositoryProvider)
          .continueReading(request: widget.request, quote: widget.quote);
      // The chat holds its pop (onExit waits for stop) while it is still saving
      // an answer; finish that first so both pops below run in the same frame.
      await ref.read(chatViewModelProvider(bookId).notifier).stop();
      if (!mounted) return;
      showToast(context, context.l10n.chatReadingPositionMovedToThisQuote);
      // The peek and the chat are dropped together and vanish instantly (no
      // slide); the result reaches the reader through a normal pop so it
      // loads the new position.
      instantRouteExit.value = true;
      Future<void>.delayed(
        const Duration(seconds: 1),
        () => instantRouteExit.value = false,
      );
      context.pop(ReaderReturn.reading);
      if (context.canPop()) {
        context.pop(ReaderReturn.reading);
      } else {
        context.go(Routes.reader(bookId));
      }
    } catch (_) {
      if (mounted) {
        showToast(context, context.l10n.chatReadingPositionHasnTMovedTry);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.request != null
        ? ref.watch(chatSourceProvider(widget.request!))
        : ref.watch(chatQuoteSourceProvider(widget.quote!));
    final location = state.asData?.value;
    if (location != null && !state.isLoading) {
      _initial ??= location;
      if (!identical(_initial!.generation, location.generation)) {
        _revoked = true;
      }
    }
    if (_initial != null && !state.isLoading && location?.available != true) {
      _revoked = true;
    }
    if (!_revoked && location?.available == true) {
      final progress = ref.watch(
        _visitProgressProvider(location!.source.anchors.first.book.bookId),
      );
      if (progress.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return ReaderView(
        key: ValueKey(widget.request ?? widget.quote),
        bookId: location.source.anchors.first.book.bookId,
        sourceVisit: location.source,
        sourceOriginalPosition: progress.asData?.value,
        onContinueReading: _saving ? null : _continue,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Layout.margin),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s4,
            children: [
              if (state.isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Text(context.l10n.chatThisSourceIsNoLongerAvailable),
              AppButton.primary(
                label: context.l10n.backToConversation,
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

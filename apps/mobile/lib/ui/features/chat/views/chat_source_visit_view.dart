import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../data/repositories/chat_repository.dart';
import '../../../core/widgets/toast.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../reader/views/reader_view.dart';
import 'chat_source_sheet.dart';

/// The resolver stays subscribed so deletes, restore and content changes revoke
/// the renderer instead of leaving a stale paragraph at the same index.
final chatQuoteSourceProvider = StreamProvider.autoDispose
    .family<ChatSourceLocation?, ChatQuote>(
      (ref, quote) => ref.watch(chatRepositoryProvider).watchQuote(quote),
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
      await ref
          .read(chatRepositoryProvider)
          .continueReading(request: widget.request, quote: widget.quote);
      if (!mounted) return;
      showToast(context, 'Posisi baca pindah ke kutipan ini.');
      context.pop(ReaderReturn.reading);
    } catch (_) {
      if (mounted) showToast(context, 'Posisi baca belum dipindah. Coba lagi.');
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
      return ReaderView(
        key: ValueKey(widget.request ?? widget.quote),
        bookId: location!.source.anchors.first.book.bookId,
        sourceVisit: location.source,
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
                const Text(
                  'Sumber ini udah gak tersedia. Posisi baca lo tetap aman.',
                ),
              AppButton.primary(
                label: 'Balik ke obrolan',
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

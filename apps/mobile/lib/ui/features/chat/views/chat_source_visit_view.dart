import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/buttons.dart';
import '../../reader/views/reader_view.dart';
import 'chat_source_sheet.dart';

/// The resolver stays subscribed so deletes, restore and content changes revoke
/// the renderer instead of leaving a stale paragraph at the same index.
class ChatSourceVisitView extends ConsumerStatefulWidget {
  const ChatSourceVisitView({super.key, required this.request});
  final ChatSourceRef request;

  @override
  ConsumerState<ChatSourceVisitView> createState() => _ChatSourceVisitState();
}

class _ChatSourceVisitState extends ConsumerState<ChatSourceVisitView> {
  ChatSourceLocation? _initial;
  bool _revoked = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatSourceProvider(widget.request));
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
        key: ValueKey(widget.request),
        bookId: widget.request.bookId,
        sourceVisit: location!.source,
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

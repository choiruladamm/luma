import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../bookshelf/view_models/bookshelf_view_model.dart';
import '../view_models/chat_view_model.dart';
import 'chat_copy.dart';

String chatBookTitle(WidgetRef ref, int bookId) =>
    ref
        .watch(booksStreamProvider)
        .asData
        ?.value
        .where((b) => b.id == bookId)
        .firstOrNull
        ?.title ??
    'Buku ini';

class ChatSessionsView extends ConsumerWidget {
  const ChatSessionsView({super.key, required this.bookId});
  final int bookId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatViewModelProvider(bookId));
    final vm = ref.read(chatViewModelProvider(bookId).notifier);
    final sessions = ref.watch(chatSessionsProvider(bookId));
    final title = chatBookTitle(ref, bookId);
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.chat(bookId));
      }
    }

    Future<void> select(int? id) async {
      if (id == null) {
        await vm.newSession();
      } else {
        await vm.openSession(id);
      }
      if (context.mounted) back();
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s5,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Space.s3),
                child: Row(
                  spacing: Space.s3,
                  children: [
                    CircleButton(
                      semanticLabel: 'Kembali ke obrolan',
                      icon: AppIcons.back,
                      onPressed: back,
                    ),
                    const Expanded(
                      child: Text(
                        'Obrolan buku ini',
                        style: StabiloType.titleMd,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                title,
                style: StabiloType.body.copyWith(color: context.stabilo.ink2),
              ),
              AppButton.primary(
                label: 'Obrolan baru',
                onPressed:
                    state.loading || state.changingSession || state.book == null
                    ? null
                    : () => select(null),
              ),
              Expanded(
                child: sessions.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: AppButton.secondary(
                      label: 'Muat ulang riwayat',
                      onPressed: () =>
                          ref.invalidate(chatSessionsProvider(bookId)),
                    ),
                  ),
                  data: (items) {
                    final own = items
                        .where((s) => s.book.bookId == bookId)
                        .toList();
                    if (own.isEmpty) {
                      return const Center(
                        child: Text(
                          'Belum ada obrolan. Mulai topik baru, yuk.',
                        ),
                      );
                    }
                    final now = DateTime.now();
                    return ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + Space.s6,
                      ),
                      itemCount: own.length + 1,
                      itemBuilder: (context, i) {
                        if (i == own.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: Space.s6),
                            child: Text(
                              'Setiap obrolan punya konteks percakapan sendiri.',
                              style: StabiloType.caption,
                            ),
                          );
                        }
                        final s = own[i],
                            group = chatTimeGroup(own[i].updatedAt, now);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (i == 0 ||
                                group !=
                                    chatTimeGroup(own[i - 1].updatedAt, now))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: Space.s3,
                                ),
                                child: Text(group, style: StabiloType.caption),
                              ),
                            SessionRow(
                              key: ValueKey(s.id),
                              session: s,
                              active: s.id == state.activeSession?.id,
                              archived:
                                  state.book != null &&
                                  s.isArchived(state.book!),
                              onTap: state.changingSession
                                  ? null
                                  : () => select(s.id),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.session,
    required this.active,
    required this.archived,
    required this.onTap,
  });
  final ChatSession session;
  final bool active, archived;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.stabilo, at = session.updatedAt.toLocal();
    final time =
        '${at.day}/${at.month} · ${at.hour.toString().padLeft(2, '0')}.${at.minute.toString().padLeft(2, '0')}';
    return Semantics(
      selected: active,
      child: Material(
        color: active ? c.muted : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.s4,
              horizontal: Space.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s2,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.title,
                        style: StabiloType.titleXs,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (active) const AppIcon(AppIcons.check),
                  ],
                ),
                Text(
                  [
                    if (active) 'Lagi dibuka',
                    if (archived) 'Arsip',
                    time,
                  ].join(' · '),
                  style: StabiloType.caption.copyWith(color: c.ink2),
                ),
                if (session.preview != null)
                  Text(
                    session.preview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.caption.copyWith(color: c.ink2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

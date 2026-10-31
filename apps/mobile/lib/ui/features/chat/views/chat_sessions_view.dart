import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/book_chat.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/ai_status.dart';
import '../../bookshelf/view_models/bookshelf_view_model.dart';
import '../view_models/chat_view_model.dart';
import 'chat_copy.dart';
import 'chat_session_menu.dart';
import '../../../core/widgets/edge_fade.dart';

String chatBookTitle(WidgetRef ref, int bookId) {
  final book = ref
      .watch(booksStreamProvider)
      .asData
      ?.value
      .where((b) => b.id == bookId)
      .firstOrNull;
  if (book == null) return 'Buku ini';
  final author = book.author?.trim();
  return author == null || author.isEmpty
      ? book.title
      : '${book.title} · $author';
}

/// Judul buku tanpa penulis, buat kalimat di tengah teks.
String chatBookName(WidgetRef ref, int bookId) =>
    ref
        .watch(booksStreamProvider)
        .asData
        ?.value
        .where((b) => b.id == bookId)
        .firstOrNull
        ?.title ??
    'buku ini';

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

    final pad = MediaQuery.paddingOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final scaledHeader =
        scaler.scale(15) * (20 / 16) + scaler.scale(13) * (18 / 13);
    final headerHeight = scaledHeader > Layout.chatHeader
        ? scaledHeader
        : Layout.chatHeader;
    final footerBottom = pad.bottom > Space.s1
        ? pad.bottom - Space.s1
        : Space.s2;
    Widget content() => sessions.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.s4),
        child: Skeleton(
          widths: [0.6, 0.85, 0.4, 0.7, 0.9, 0.4],
          lineExtent: Space.s8,
        ),
      ),
      error: (_, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.s3,
          children: [
            AppIcon(AppIcons.alertCircle, color: context.stabilo.danger),
            const Text('Riwayatnya gak kebuka.', style: StabiloType.titleXs),
            Text(
              'Obrolan lo aman kok. Coba muat ulang bentar lagi.',
              textAlign: TextAlign.center,
              style: StabiloType.caption.copyWith(color: context.stabilo.ink2),
            ),
            AppButton.secondary(
              label: 'Muat ulang',
              height: Layout.touch,
              onPressed: () => ref.invalidate(chatSessionsProvider(bookId)),
            ),
          ],
        ),
      ),
      data: (items) {
        final own = items.where((s) => s.book.bookId == bookId).toList();
        if (own.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.s2,
              children: [
                const Text('Belum ada obrolan.', style: StabiloType.titleXs),
                Text(
                  'Obrolan yang lo mulai bakal muncul di sini, dipisah per sesi.',
                  textAlign: TextAlign.center,
                  style: StabiloType.caption.copyWith(
                    color: context.stabilo.ink2,
                  ),
                ),
              ],
            ),
          );
        }
        final now = DateTime.now();
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            Space.s4,
            pad.top + headerHeight + Space.s2,
            Space.s4,
            pad.bottom + 100,
          ),
          itemCount: own.length,
          itemBuilder: (context, i) {
            final session = own[i],
                group = chatTimeGroup(session.updatedAt, now);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (i == 0 || group != chatTimeGroup(own[i - 1].updatedAt, now))
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      Space.s2,
                      i == 0 ? Space.s2 : 22,
                      Space.s2,
                      6,
                    ),
                    child: Text(
                      group,
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.stabilo.ink3,
                      ),
                    ),
                  ),
                SessionRow(
                  key: ValueKey(session.id),
                  session: session,
                  active: session.id == state.activeSession?.id,
                  archived:
                      state.book != null && session.isArchived(state.book!),
                  onMenu: state.changingSession
                      ? null
                      : () => showChatSessionMenu(
                          context,
                          vm,
                          state,
                          target: session,
                        ),
                  onTap: state.changingSession
                      ? null
                      : () => select(session.id),
                ),
              ],
            );
          },
        );
      },
    );
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: EdgeFadeScroll(
              top: EdgeFadeSide(Space.s5, clear: pad.top + headerHeight),
              bottom: EdgeFadeSide(Space.s5, clear: footerBottom + 56),
              child: content(),
            ),
          ),
          Positioned(
            left: Space.s4,
            right: Space.s4,
            top: pad.top,
            child: Container(
              color: context.stabilo.canvas,
              constraints: const BoxConstraints(minHeight: Layout.chatHeader),
              child: Row(
                spacing: Space.s2,
                children: [
                  CircleButton(
                    semanticLabel: 'Kembali ke obrolan',
                    icon: AppIcons.back,
                    onPressed: back,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Riwayat obrolan',
                          style: StabiloType.titleXs.copyWith(fontSize: 15),
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
                ],
              ),
            ),
          ),
          Positioned(
            left: Space.s4,
            right: Space.s4,
            bottom: footerBottom,
            child: AppButton.primary(
              label: 'Obrolan baru',
              height: 56,
              pill: true,
              onPressed:
                  state.loading || state.changingSession || state.book == null
                  ? null
                  : () => select(null),
            ),
          ),
        ],
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
    this.onMenu,
  });
  final ChatSession session;
  final bool active, archived;
  final VoidCallback? onTap, onMenu;
  @override
  Widget build(BuildContext context) {
    final c = context.stabilo, at = session.updatedAt.toLocal();
    final time =
        '${at.day}/${at.month} · ${at.hour.toString().padLeft(2, '0')}.${at.minute.toString().padLeft(2, '0')}';
    Widget badge(String label, {bool active = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 2),
      decoration: BoxDecoration(
        color: active ? c.accent : c.muted,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Text(
        label,
        style: StabiloType.caption.copyWith(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w700,
          color: active ? c.onAccent : c.ink2,
        ),
      ),
    );
    return Semantics(
      selected: active,
      child: Material(
        color: active ? c.muted : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Padding(
            padding: const EdgeInsets.only(
              left: Space.s3,
              top: Space.s3,
              bottom: Space.s3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(
                        session.title,
                        style: StabiloType.titleXs.copyWith(fontSize: 15.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (session.preview != null)
                        Text(
                          session.preview!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.caption.copyWith(color: c.ink2),
                        ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: Space.s2,
                        children: [
                          Text(
                            'Diperbarui $time',
                            style: StabiloType.caption.copyWith(color: c.ink2),
                          ),
                          if (active) badge('Lagi dibuka', active: true),
                          if (archived) badge('Arsip'),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Menu ${session.title}',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  padding: EdgeInsets.zero,
                  icon: AppIcon(AppIcons.more, color: c.ink2),
                  onPressed: onMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

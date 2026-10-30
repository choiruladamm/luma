import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/core/theme/stabilo_tokens.dart';
import '../domain/models/book_chat.dart';
import '../ui/features/chat/view_models/chat_view_model.dart';
import '../ui/features/chat/views/chat_view.dart';
import '../ui/features/chat/views/chat_source_visit_view.dart';
import '../ui/features/chat/views/chat_sessions_view.dart';
import '../ui/features/bookshelf/views/bookshelf_view.dart';
import '../ui/features/breakdown/views/breakdown_view.dart';
import '../ui/features/reader/views/reader_view.dart';
import '../ui/features/settings/views/settings_view.dart';

abstract final class Routes {
  static const home = '/';
  static const settings = '/settings';
  static String chat(int bookId) => '/reader/$bookId/chat';
  static String chatSource(ChatSourceRef source) =>
      '${chat(source.bookId)}/source/${source.sessionId}/${source.turnId}/${source.attempt}/${Uri.encodeComponent(source.sourceId)}';
  static String chatQuote(int bookId) => '${chat(bookId)}/quote';
  static String chatSessions(int bookId) => '${chat(bookId)}/sessions';
  static String reader(int bookId) => '/reader/$bookId';

  /// Bedahin satu grup. Cuma di-`push` dari sheet Artinya: sheet-nya tetep
  /// di bawah, balik = balik ke sheet.
  static String breakdown(int bookId, int chapterId, int groupIndex) =>
      '/reader/$bookId/breakdown/$chapterId/$groupIndex';
}

// Sheet artinya, Aa, dan Daftar isi bukan route: pakai showModalBottomSheet.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(path: Routes.home, builder: (_, _) => const BookshelfView()),
      GoRoute(
        path: '/reader/:bookId',
        builder: (_, state) =>
            ReaderView(bookId: int.parse(state.pathParameters['bookId']!)),
        routes: [
          GoRoute(
            path: 'breakdown/:chapterId/:groupIndex',
            pageBuilder: (context, state) {
              final entry = state.extra;
              final view = BreakdownView(
                chatContext: entry is ChatLaunchContext ? entry : null,
                bookId: int.parse(state.pathParameters['bookId']!),
                group: (
                  chapterId: int.parse(state.pathParameters['chapterId']!),
                  groupIndex: int.parse(state.pathParameters['groupIndex']!),
                ),
              );
              // Kurangi gerakan: fade, gak geser.
              if (!MediaQuery.disableAnimationsOf(context)) {
                return MaterialPage(key: state.pageKey, child: view);
              }
              return CustomTransitionPage(
                key: state.pageKey,
                transitionDuration: Motion.reducedFade,
                reverseTransitionDuration: Motion.reducedFade,
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
                child: view,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/reader/:bookId/chat',
        onExit: (context, state) async {
          final id = int.tryParse(state.pathParameters['bookId'] ?? '');
          if (id != null && id > 0) {
            await ref.read(chatViewModelProvider(id).notifier).stop();
          }
          return true;
        },
        builder: (_, state) {
          final id = int.tryParse(state.pathParameters['bookId'] ?? '');
          if (id == null || id <= 0) return const _InvalidChatRoute();
          final extra = state.extra;
          final launch = extra is ChatLaunchContext && extra.book.bookId == id
              ? extra
              : null;
          return ChatView(key: ValueKey(id), bookId: id, launch: launch);
        },
        routes: [
          GoRoute(
            path: 'source/:sessionId/:turnId/:attempt/:sourceId',
            builder: (_, state) {
              int? id(String key) =>
                  int.tryParse(state.pathParameters[key] ?? '');
              final book = id('bookId'),
                  session = id('sessionId'),
                  turn = id('turnId'),
                  attempt = id('attempt');
              final source = state.pathParameters['sourceId'];
              if (book == null ||
                  book <= 0 ||
                  session == null ||
                  session <= 0 ||
                  turn == null ||
                  turn <= 0 ||
                  attempt == null ||
                  attempt <= 0 ||
                  source == null ||
                  source.isEmpty) {
                return const _InvalidChatRoute();
              }
              return ChatSourceVisitView(
                request: (
                  bookId: book,
                  sessionId: session,
                  turnId: turn,
                  attempt: attempt,
                  sourceId: source,
                ),
              );
            },
          ),
          GoRoute(
            path: 'quote',
            builder: (_, state) {
              final quote = state.extra;
              final bookId = int.tryParse(state.pathParameters['bookId'] ?? '');
              if (quote is! ChatQuote ||
                  quote.anchors.any((a) => a.book.bookId != bookId)) {
                return const _InvalidChatRoute();
              }
              return ChatSourceVisitView(quote: quote);
            },
          ),
          GoRoute(
            path: 'sessions',
            builder: (_, state) {
              final id = int.tryParse(state.pathParameters['bookId'] ?? '');
              if (id == null || id <= 0) return const _InvalidChatRoute();
              return ChatSessionsView(bookId: id);
            },
          ),
        ],
      ),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsView()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _InvalidChatRoute extends StatelessWidget {
  const _InvalidChatRoute();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: TextButton(
          onPressed: () => context.go(Routes.home),
          child: const Text('Alamat obrolan gak valid. Kembali'),
        ),
      ),
    ),
  );
}

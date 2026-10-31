import 'package:flutter/cupertino.dart' show CupertinoPage;
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
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['bookId'] ?? '');
          if (id == null || id <= 0) {
            return _slidePage(context, state, const _InvalidChatRoute());
          }
          final extra = state.extra;
          final launch = extra is ChatLaunchContext && extra.book.bookId == id
              ? extra
              : null;
          return _instantExitPage(
            context,
            state,
            ChatView(key: ValueKey(id), bookId: id, launch: launch),
          );
        },
        routes: [
          GoRoute(
            path: 'source/:sessionId/:turnId/:attempt/:sourceId',
            pageBuilder: (context, state) {
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
                return _slidePage(context, state, const _InvalidChatRoute());
              }
              return _instantExitPage(
                context,
                state,
                ChatSourceVisitView(
                  request: (
                    bookId: book,
                    sessionId: session,
                    turnId: turn,
                    attempt: attempt,
                    sourceId: source,
                  ),
                ),
                holdOnInstantExit: true,
              );
            },
          ),
          GoRoute(
            path: 'quote',
            pageBuilder: (context, state) {
              final quote = state.extra;
              final bookId = int.tryParse(state.pathParameters['bookId'] ?? '');
              if (quote is! ChatQuote ||
                  quote.anchors.any((a) => a.book.bookId != bookId)) {
                return _slidePage(context, state, const _InvalidChatRoute());
              }
              return _instantExitPage(
                context,
                state,
                ChatSourceVisitView(quote: quote),
                holdOnInstantExit: true,
              );
            },
          ),
          GoRoute(
            path: 'sessions',
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['bookId'] ?? '');
              if (id == null || id <= 0) {
                return _slidePage(context, state, const _InvalidChatRoute());
              }
              return _slidePage(context, state, ChatSessionsView(bookId: id));
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

/// Nyala sebentar pas "Lanjut baca" di layar intip: halaman yang keluar langsung
/// ilang (tanpa animasi geser) biar pindah ke reader terasa mulus.
final instantRouteExit = ValueNotifier<bool>(false);

/// Layar chat + intip sumber: geser masuk seperti [_slidePage], tapi keluarnya
/// bisa instan lewat [instantRouteExit] ("Lanjut baca"). Kurangi gerakan: fade.
Page<void> _instantExitPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  bool holdOnInstantExit = false,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return _slidePage(context, state, child);
  }
  final slide = Tween(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: Motion.sheetOpenCurve));
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: Motion.sheetOpen,
    reverseTransitionDuration: Motion.sheetClose,
    transitionsBuilder: (ctx, animation, _, child) => AnimatedBuilder(
      animation: Listenable.merge([animation, instantRouteExit]),
      child: child,
      builder: (_, child) {
        if (!instantRouteExit.value) {
          return SlideTransition(
            position: animation.drive(slide),
            child: child,
          );
        }
        // "Lanjut baca": rute chat dicabut go_router 1-2 frame setelah layar
        // intip, jadi chat dikosongin begitu flag nyala (masih ketutup intip)
        // biar gak kedip. Intip tetap nutup diam sampai animasi baliknya lewat
        // setengah, baru ilang.
        final reversing = animation.status == AnimationStatus.reverse;
        if (holdOnInstantExit) {
          return reversing && animation.value <= 0.5
              ? const SizedBox.shrink()
              : child!;
        }
        return reversing
            ? const SizedBox.shrink()
            : ColoredBox(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                child: const SizedBox.expand(),
              );
      },
    ),
    child: child,
  );
}

/// Geser ala iOS di semua platform (opaque, ada parallax + swipe-back), biar
/// header dua layar gak numpuk transparan pas pindah. Kurangi gerakan: fade.
Page<void> _slidePage(BuildContext context, GoRouterState state, Widget child) {
  if (!MediaQuery.disableAnimationsOf(context)) {
    return CupertinoPage<void>(key: state.pageKey, child: child);
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: Motion.reducedFade,
    reverseTransitionDuration: Motion.reducedFade,
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    child: child,
  );
}

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

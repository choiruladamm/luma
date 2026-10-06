import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/features/bookshelf/views/bookshelf_view.dart';
import '../ui/features/reader/views/reader_view.dart';
import '../ui/features/settings/views/settings_view.dart';

abstract final class Routes {
  static const home = '/';
  static const settings = '/settings';
  static String reader(int bookId) => '/reader/$bookId';
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
      ),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsView()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

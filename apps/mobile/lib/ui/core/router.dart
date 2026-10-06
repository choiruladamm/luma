import 'package:go_router/go_router.dart';

import '../features/bookshelf/views/bookshelf_screen.dart';
import '../features/reader/views/reader_screen.dart';
import '../features/settings/views/settings_screen.dart';

// Sheet artinya, Aa, dan Daftar isi bukan route: pakai showModalBottomSheet.
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const BookshelfScreen()),
    GoRoute(
      path: '/reader/:bookId',
      builder: (_, state) =>
          ReaderScreen(bookId: int.parse(state.pathParameters['bookId']!)),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

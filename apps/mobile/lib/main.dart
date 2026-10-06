import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/services/file_storage.dart';
import 'routing/router.dart';
import 'ui/core/theme/stabilo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await FileStorage.open();
  runApp(
    ProviderScope(
      overrides: [fileStorageProvider.overrideWithValue(storage)],
      child: const LumaApp(),
    ),
  );
}

class LumaApp extends ConsumerWidget {
  const LumaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Luma',
      debugShowCheckedModeBanner: false,
      theme: stabiloTheme(Brightness.light),
      darkTheme: stabiloTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

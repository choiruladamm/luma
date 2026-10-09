import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/repositories/settings_repository.dart';
import 'data/services/file_storage.dart';
import 'domain/models/reader_prefs.dart';
import 'routing/router.dart';
import 'ui/core/theme/stabilo_theme.dart';
import 'ui/features/splash/splash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await FileStorage.open();
  runApp(
    ProviderScope(
      overrides: [fileStorageProvider.overrideWithValue(storage)],
      child: const LumaApp(splash: true),
    ),
  );
}

class LumaApp extends ConsumerWidget {
  /// [splash] = animasi splash → rak di atas app (cuma dari `main`, test
  /// gak mau ketutup lapisannya).
  const LumaApp({super.key, this.splash = false});

  final bool splash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Luma',
      debugShowCheckedModeBanner: false,
      theme: stabiloTheme(Brightness.light),
      darkTheme: stabiloTheme(Brightness.dark),
      // Tema dari Aa. Sebelum setelan kebaca: ikut sistem.
      themeMode: switch (ref.watch(readerPrefsProvider).value?.theme) {
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
        AppTheme.system || null => ThemeMode.system,
      },
      builder: (context, child) =>
          SplashGate(enabled: splash, child: child ?? const SizedBox.shrink()),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/repositories/settings_repository.dart';
import 'data/services/file_storage.dart';
import 'domain/models/reader_prefs.dart';
import 'routing/router.dart';
import 'l10n/app_localizations.dart';
import 'ui/core/theme/stabilo_theme.dart';
import 'ui/features/discover/views/download_toasts.dart';
import 'ui/features/settings/views/cloud_backup_trigger.dart';
import 'ui/features/settings/views/sync_trigger.dart';
import 'ui/features/splash/splash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await FileStorage.open();
  runApp(
    ProviderScope(
      overrides: [fileStorageProvider.overrideWithValue(storage)],
      child: const LumaApp(splash: true, autoBackup: true),
    ),
  );
}

class LumaApp extends ConsumerWidget {
  /// [splash] = splash animation → shelf over the app (only from `main`; tests
  /// don't want their layer covered).
  const LumaApp({super.key, this.splash = false, this.autoBackup = false});

  final bool splash;

  /// Automatic cloud backup + sync push (only from `main`: tests have no real DB).
  final bool autoBackup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLocaleProvider);
    return MaterialApp.router(
      locale: Locale(language.value ?? 'id'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      title: 'Luma',
      debugShowCheckedModeBanner: false,
      theme: stabiloTheme(Brightness.light),
      darkTheme: stabiloTheme(Brightness.dark),
      // Theme from Aa. Before the settings are read: follow the system.
      themeMode: switch (ref.watch(readerPrefsProvider).value?.theme) {
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
        AppTheme.system || null => ThemeMode.system,
      },
      builder: (context, child) => SplashGate(
        enabled: splash,
        child: language.isLoading && !language.hasValue
            ? const SizedBox.expand()
            : DownloadToasts(
                child: autoBackup
                    ? CloudBackupTrigger(
                        child: SyncTrigger(
                          child: child ?? const SizedBox.shrink(),
                        ),
                      )
                    : child ?? const SizedBox.shrink(),
              ),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

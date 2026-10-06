import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/core/router.dart';
import 'ui/core/theme/stabilo_theme.dart';

void main() {
  runApp(const ProviderScope(child: LumaApp()));
}

class LumaApp extends StatelessWidget {
  const LumaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Luma',
      debugShowCheckedModeBanner: false,
      theme: stabiloTheme(Brightness.light),
      darkTheme: stabiloTheme(Brightness.dark),
      routerConfig: router,
    );
  }
}

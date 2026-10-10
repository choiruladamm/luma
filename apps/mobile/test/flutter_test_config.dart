import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file. Each test opens its own in-memory database,
/// so drift's "created AppDatabase multiple times" warning is just noise here.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // A tap/drag that misses its target must fail, not just print a warning.
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}

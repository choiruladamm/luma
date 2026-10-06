import 'dart:async';

import 'package:drift/drift.dart';

/// Runs before every test file. Each test opens its own in-memory database,
/// so drift's "created AppDatabase multiple times" warning is just noise here.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}

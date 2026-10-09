import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test('success always counts as saved', () {
    for (final p in TargetPlatform.values) {
      expect(shareSaved(ShareResultStatus.success, p), isTrue);
    }
  });

  test('dismissed is never saved', () {
    for (final p in TargetPlatform.values) {
      expect(shareSaved(ShareResultStatus.dismissed, p), isFalse);
    }
  });

  test('unavailable counts as saved on Android only', () {
    expect(
      shareSaved(ShareResultStatus.unavailable, TargetPlatform.android),
      isTrue,
    );
    expect(
      shareSaved(ShareResultStatus.unavailable, TargetPlatform.iOS),
      isFalse,
    );
  });
}

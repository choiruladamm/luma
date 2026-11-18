import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet (iOS: Save to Files, iCloud Drive, AirDrop;
/// Android: Drive, Downloads, and so on).
class ShareService {
  /// Returns true when the user actually saved or sent the file, false when the sheet was dismissed.
  Future<bool> shareFile(File file, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
    return shareSaved(result.status);
  }
}

/// Returns whether a share [status] counts as saved.
///
/// Android share targets often report `unavailable` (no result callback), so
/// that counts as success: recording a backup that was actually cancelled is
/// safer than leaving the backup banner on forever. `dismissed` still counts
/// as cancelled.
@visibleForTesting
bool shareSaved(ShareResultStatus status, [TargetPlatform? platform]) {
  if (status == ShareResultStatus.success) return true;
  return status == ShareResultStatus.unavailable &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android;
}

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

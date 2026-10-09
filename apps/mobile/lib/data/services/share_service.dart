import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Menu share sistem (iOS: Simpan ke Files, iCloud Drive, AirDrop; Android:
/// Drive, Downloads, dll).
class ShareService {
  /// true = user beneran nyimpen / ngirim, false = ditutup.
  Future<bool> shareFile(File file, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
    return shareSaved(result.status);
  }
}

/// Status share → "udah disimpen". Di Android target share sering balik
/// `unavailable` (gak ada callback hasil), jadi dianggap sukses: lebih aman
/// kecatet padahal dibatalin daripada banner backup nyala terus. `dismissed`
/// tetap batal.
@visibleForTesting
bool shareSaved(ShareResultStatus status, [TargetPlatform? platform]) {
  if (status == ShareResultStatus.success) return true;
  return status == ShareResultStatus.unavailable &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android;
}

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

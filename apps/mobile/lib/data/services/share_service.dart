import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Menu share iOS (Simpan ke Files, iCloud Drive, AirDrop).
class ShareService {
  /// true = user beneran nyimpen / ngirim, false = ditutup.
  Future<bool> shareFile(File file, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
    return result.status == ShareResultStatus.success;
  }
}

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

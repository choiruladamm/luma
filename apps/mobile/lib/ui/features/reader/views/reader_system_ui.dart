import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps system bars in sync with the reading capsule.
///
/// On Android, bars revealed by an edge swipe hide again after a delay.
/// On iOS, the home indicator remains visible.
class ReaderSystemUi {
  ReaderSystemUi({
    required this.isVisit,
    required this.barsShown,
    required this.offReader,
    required this.mounted,
  });

  /// Whether this reader is previewing a chat source and leaves system UI alone.
  final bool isVisit;

  /// Whether the capsule is visible or hiding the status bar is disabled.
  final bool Function() barsShown;

  /// Whether another screen is above the reader.
  final bool Function() offReader;
  final bool Function() mounted;

  Timer? _rehide;

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  void attach() {
    if (!_android || isVisit) return;
    SystemChrome.setSystemUIChangeCallback((visible) async {
      if (!visible || !mounted()) return;
      _rehide?.cancel();
      _rehide = Timer(const Duration(seconds: 2), sync);
    });
  }

  /// Shows system bars while another screen is open.
  void edgeToEdge() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  void sync() {
    if (offReader() || isVisit) return edgeToEdge();
    final show = barsShown();
    if (_android) {
      SystemChrome.setEnabledSystemUIMode(
        show ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      );
      return;
    }
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: show ? SystemUiOverlay.values : const [SystemUiOverlay.bottom],
    );
  }

  /// Restores system bars when leaving the reader.
  void release() {
    _rehide?.cancel();
    if (_android && !isVisit) SystemChrome.setSystemUIChangeCallback(null);
    if (_android) return edgeToEdge();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }
}

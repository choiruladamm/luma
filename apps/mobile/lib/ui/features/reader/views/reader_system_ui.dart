import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Status bar (dan navbar Android) ngikutin kapsul baca. Android: immersive
/// sticky, bar yang kebuka swipe tepi ngumpet lagi sesudah jeda. iOS: bar
/// bawah (home indicator) dibiarin.
class ReaderSystemUi {
  ReaderSystemUi({
    required this.isVisit,
    required this.barsShown,
    required this.offReader,
    required this.mounted,
  });

  /// Lagi ngintip sumber obrolan: sistem UI gak diatur layar ini.
  final bool isVisit;

  /// Kapsul keliatan atau setelan "ngumpetin status bar" mati.
  final bool Function() barsShown;

  /// Layar lain (Bedahin, Pengaturan) lagi di atas layar baca.
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

  /// Layar lain bukan layar baca: bar sistem tampil selama di sana.
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

  /// Keluar dari layar baca: bar balik normal.
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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/nav_bar.dart';

/// Naik tiap tab aktif ditap lagi (board NavBar: scroll ke atas). Layar tab
/// `ref.listen` dan gulung ke atas sendiri.
class TabReselect extends Notifier<int> {
  @override
  int build() => 0;

  LumaTab? last;

  void bump(LumaTab tab) {
    last = tab;
    state++;
  }
}

final tabReselectProvider = NotifierProvider<TabReselect, int>(TabReselect.new);

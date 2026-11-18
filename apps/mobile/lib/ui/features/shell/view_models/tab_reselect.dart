import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/nav_bar.dart';

/// Increments each time the active tab is tapped again (board NavBar: scroll to
/// top). Tab screens `ref.listen` and scroll up themselves.
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

import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';

/// Tab Cari buku. Isi layar (Top chart, hasil, state) nyusul di #167; ini
/// cuma pintu masuknya biar bar punya tiga tab.
class DiscoverView extends StatelessWidget {
  const DiscoverView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: Layout.topBar,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text('Cari buku', style: StabiloType.titleLg),
                  ),
                ),
              ),
              Text('Nyusul.', style: StabiloType.body.copyWith(color: c.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}

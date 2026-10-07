import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/ai_results_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../domain/models/ai_model.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/dialog.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/field.dart';
import '../view_models/settings_view_model.dart';

/// Pengaturan app (board 23 Pengaturan app): API key, model AI, cache
/// terjemahan. Bagian Backup & pulihin nyusul di #24–#26.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _key = TextEditingController();

  /// Ngecek key ke OpenRouter nunggu ngetiknya berhenti bentar.
  Timer? _checkLater;

  @override
  void initState() {
    super.initState();
    ref.read(apiKeyStoreProvider).read().then((key) {
      if (mounted && _key.text.isEmpty) _key.text = key ?? '';
    });
  }

  @override
  void dispose() {
    _checkLater?.cancel();
    _key.dispose();
    super.dispose();
  }

  /// Disimpen tiap diubah (biasanya sekali paste); kosong = dihapus.
  Future<void> _saveKey(String key) async {
    await ref.read(apiKeyStoreProvider).write(key);
    _checkLater?.cancel();
    _checkLater = Timer(const Duration(milliseconds: 600), () {
      if (mounted) ref.invalidate(apiKeyProvider);
    });
  }

  Future<void> _clearCache() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Hapus cache terjemahan?',
      message:
          'Semua terjemahan yang udah kesimpen bakal ilang. Paragraf yang '
          'dibuka lagi manggil AI ulang dan motong saldo lagi.',
      confirmLabel: 'Hapus',
    );
    if (ok) await ref.read(aiResultsRepositoryProvider).clear();
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(aiModelProvider).value ?? defaultAiModel;
    final cache = ref.watch(aiCacheStatsProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header nempel; isi di bawahnya mudar pas lewat (board EdgeFade).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
              child: SizedBox(
                height: Layout.topBar,
                child: Row(
                  spacing: Space.s3,
                  children: [
                    CircleButton(
                      semanticLabel: 'Balik ke rak',
                      icon: AppIcons.back,
                      onPressed: () => context.pop(),
                    ),
                    Semantics(
                      header: true,
                      child: Text('Pengaturan', style: StabiloType.titleLg),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: EdgeFadeScroll(
                // Bawah edge-to-edge, padding akhir = safe area.
                bottom: EdgeFadeSide.none,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    Layout.margin,
                    22,
                    Layout.margin,
                    MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    AppField(
                      label: 'API key OpenRouter',
                      controller: _key,
                      secret: true,
                      onChanged: _saveKey,
                    ),
                    const SizedBox(height: Space.s2),
                    _KeyStatus(ok: ref.watch(apiKeyCheckProvider).value),
                    const SizedBox(height: 22),
                    _Section(
                      label: 'Model AI',
                      note: 'Biayanya kepotong dari saldo akun OpenRouter lo.',
                      child: _ModelPicker(
                        selected: model,
                        onSelect: (id) =>
                            ref.read(settingsRepositoryProvider).saveModel(id),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _Section(
                      label: 'Penyimpanan',
                      child: _CacheRow(stats: cache, onClear: _clearCache),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Di bawah field key: "Key-nya jalan" kalau OpenRouter nerima, "ditolak"
/// kalau 401/403, selain itu (belum ada / lagi ngecek / offline) penjelasan
/// tempat nyimpennya.
class _KeyStatus extends StatelessWidget {
  const _KeyStatus({required this.ok});

  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final small = StabiloType.caption.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: c.ink2,
    );
    if (ok == null) {
      return Text(
        'Disimpen di Keychain iPhone, gak dikirim ke mana-mana selain '
        'OpenRouter.',
        style: small,
      );
    }
    final label = StabiloType.caption.copyWith(fontWeight: FontWeight.w600);
    return Row(
      children: [
        Expanded(
          child: ok!
              ? Row(
                  spacing: 6,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                      child: AppIcon(
                        AppIcons.check,
                        size: 11,
                        color: c.onAccent,
                      ),
                    ),
                    Text('Key-nya jalan', style: label.copyWith(color: c.ink)),
                  ],
                )
              : Text(
                  'Key-nya ditolak OpenRouter',
                  style: label.copyWith(color: c.danger),
                ),
        ),
        Text('Disimpen di Keychain', style: small),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, this.note, required this.child});

  final String label;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Text(
          label,
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: c.ink2,
          ),
        ),
        child,
        if (note != null)
          Text(
            note!,
            style: StabiloType.caption.copyWith(
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
              color: c.ink2,
            ),
          ),
      ],
    );
  }
}

/// RadioRow (board Komponen 04): titik kuning + nama + model ID mono.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Column(
        children: [
          for (final (i, m) in aiModels.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.menuLine),
            _ModelRow(
              model: m,
              selected: m.id == selected,
              onTap: () => onSelect(m.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final AiModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: model.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: 10,
            ),
            child: Row(
              spacing: Space.s3,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? c.accent : null,
                    border: Border.all(
                      color: selected ? c.accentBorder : c.fieldLine,
                      width: Layout.outline,
                    ),
                  ),
                  child: selected
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.onAccent,
                          ),
                        )
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Wrap(
                        spacing: Space.s2,
                        runSpacing: Space.s1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            model.label,
                            style: StabiloType.label.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          if (model.id == defaultAiModel)
                            Container(
                              height: 20,
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.s2,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.muted,
                                borderRadius: BorderRadius.circular(Radii.full),
                              ),
                              child: Text(
                                'Default · paling hemat',
                                style: StabiloType.micro.copyWith(
                                  height: 1,
                                  color: c.ink,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        model.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.mono.copyWith(
                          fontSize: 12,
                          color: c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// SettingsRow cache: jumlah paragraf + ukuran, tombol hapus warna danger.
class _CacheRow extends StatelessWidget {
  const _CacheRow({required this.stats, required this.onClear});

  final AiCacheStats? stats;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final empty = stats == null || stats!.paragraphs == 0;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(Space.s4, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  'Cache terjemahan',
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                Text(
                  stats == null
                      ? ' '
                      : '${thousands(stats!.paragraphs)} paragraf · '
                            '${fileSize(stats!.bytes)}',
                  style: StabiloType.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: c.ink2,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: empty ? null : onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, Layout.touch),
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              backgroundColor: c.muted,
              foregroundColor: c.danger,
              disabledForegroundColor: c.ink3,
              disabledBackgroundColor: c.muted,
              shape: const StadiumBorder(),
              textStyle: StabiloType.label.copyWith(fontSize: 14),
            ),
            child: const Text('Hapus cache'),
          ),
        ],
      ),
    );
  }
}

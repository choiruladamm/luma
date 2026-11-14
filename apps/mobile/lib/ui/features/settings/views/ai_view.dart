import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../domain/models/ai_model.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/field.dart';
import '../view_models/ai_quota_view_model.dart';
import '../view_models/settings_view_model.dart';
import 'ai_source_section.dart'
    show ownKeyRequestProvider, showBackToFreeSheet, showModelPickerSheet;
import 'settings_page.dart';

String _modelLabel(String id) {
  for (final m in aiModels) {
    if (m.id == id) return m.label;
  }
  return id;
}

/// Pengaturan → AI (board "Pengaturan · 03–06"): sumber AI, model gratis atau
/// key sendiri + status key.
class AiView extends ConsumerStatefulWidget {
  const AiView({super.key});

  @override
  ConsumerState<AiView> createState() => _AiViewState();
}

class _AiViewState extends ConsumerState<AiView> {
  final _key = TextEditingController();
  final _focus = FocusNode();

  /// Tab yang dipilih. Null = ikut sumber yang kesimpen (ada key = Key sendiri).
  AiSource? _picked;

  ApiKeyEntry get _entry => ref.read(apiKeyEntryProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Key yang kesimpen ditampilin di field (disamarin).
    ref.read(apiKeyStoreProvider).read().then((key) {
      if (mounted && _key.text.isEmpty) _key.text = key ?? '';
    });
    if (ref.read(ownKeyRequestProvider) > 0) _openOwnKey(focus: true);
  }

  @override
  void dispose() {
    _key.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openOwnKey({bool focus = false}) {
    setState(() => _picked = AiSource.own);
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  Future<void> _selectSource(AiSource source, AiSource stored) async {
    if (source == AiSource.own) return _openOwnKey(focus: true);
    // Masih ada key kesimpen: balik ke gratis = hapus key.
    if (stored == AiSource.own) return _backToFree();
    setState(() => _picked = AiSource.subsidy);
  }

  Future<void> _backToFree() async {
    final ok = await showBackToFreeSheet(context);
    if (!ok || !mounted) return;
    _key.clear();
    _entry.clear();
    await ref.read(settingsRepositoryProvider).saveModel(defaultAiModel);
    ref.invalidate(aiSourceProvider);
    if (mounted) setState(() => _picked = AiSource.subsidy);
    await ref.read(aiQuotaProvider.notifier).refresh(force: true);
  }

  Future<void> _pickOwnModel(String current) async {
    final picked = await showModelPickerSheet(
      context,
      source: AiSource.own,
      current: current,
      onUseOwnKey: () {},
    );
    if (picked != null) {
      await ref.read(settingsRepositoryProvider).saveModel(picked);
    }
  }

  /// "Cek lagi": key kesimpen = cek ulang yang kesimpen, key baru yang
  /// ditolak = kirim ulang teks di field.
  void _recheck(KeyStatus status) {
    if (status == KeyStatus.refused) {
      _entry.edit(_key.text);
    } else {
      ref.invalidate(apiKeyEntryProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ownKeyRequestProvider, (_, _) => _openOwnKey(focus: true));
    ref.listen(apiKeyEntryProvider, (prev, next) {
      // Key kesimpen / kehapus: sumber AI ikut berubah.
      if (next == KeyStatus.valid || next == KeyStatus.idle) {
        ref.invalidate(aiSourceProvider);
      }
      // Key dihapus lewat ×: model di luar model gratis bakal ditolak
      // guardrail, jadi balik ke default.
      if (next == KeyStatus.idle && _key.text.isEmpty) {
        final model = ref.read(aiModelProvider).value ?? defaultAiModel;
        final allowed =
            ref.read(subsidyModelsProvider).value ?? subsidyModelIds;
        if (!allowed.contains(model)) {
          ref.read(settingsRepositoryProvider).saveModel(defaultAiModel);
        }
      }
    });
    final l = context.l10n;
    final stored = ref.watch(aiSourceProvider).value ?? AiSource.subsidy;
    final source = _picked ?? stored;
    final model = ref.watch(aiModelProvider).value ?? defaultAiModel;
    final status = ref.watch(apiKeyEntryProvider);
    final rejected =
        status == KeyStatus.rejected || status == KeyStatus.refused;
    final freeIds = ref.watch(subsidyModelsProvider).value ?? subsidyModelIds;

    return SettingsPage(
      title: l.aiSection,
      children: [
        _Labeled(
          label: l.quotaSource,
          child: _SourceTabs(
            selected: source,
            onSelect: (s) => _selectSource(s, stored),
          ),
        ),
        if (source == AiSource.subsidy) ...[
          _Labeled(
            label: l.settingsAiFreeModelsLabel(freeIds.length),
            child: _FreeModelList(
              ids: freeIds,
              current: model,
              onSelect: (id) =>
                  ref.read(settingsRepositoryProvider).saveModel(id),
            ),
          ),
          _Note(icon: AppIcons.key, text: l.settingsAiMoreModelsHint),
        ] else ...[
          _Labeled(
            label: l.settingsOpenrouterApiKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s2,
              children: [
                AppField(
                  label: l.settingsOpenrouterApiKey,
                  showLabel: false,
                  controller: _key,
                  focusNode: _focus,
                  hint: 'sk-or-v1-…',
                  secret: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  // Lagi ngedit key: tab Key sendiri tetap kebuka walau field
                  // dikosongin (sumber yang kesimpen jadi kuota gratis).
                  onChanged: (text) {
                    _picked = AiSource.own;
                    _entry.edit(text);
                  },
                  onClear: () {
                    _picked = AiSource.own;
                    _key.clear();
                    _entry.clear();
                  },
                ),
                _KeyStatusRow(
                  status: status,
                  onRecheck: () => _recheck(status),
                ),
              ],
            ),
          ),
          if (rejected)
            _RejectedBox(fallback: status == KeyStatus.rejected)
          else
            _Note(icon: AppIcons.info, text: l.aiOwnKeyCost),
          _ModelRow(
            id: model,
            subtitle: status == KeyStatus.rejected
                ? l.settingsAiModelFallsBack(model)
                : model,
            onTap: () => _pickOwnModel(model),
          ),
          if (stored == AiSource.own)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _backToFree,
                child: Text(
                  l.aiBackToFree,
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    color: context.stabilo.ink,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.s2,
    children: [
      Text(
        label,
        style: StabiloType.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: context.stabilo.ink2,
        ),
      ),
      child,
    ],
  );
}

class _SourceTabs extends StatelessWidget {
  const _SourceTabs({required this.selected, required this.onSelect});

  /// Tinggi tab 38 di dalam trek 46 (board: padding 4).
  static const _track = 46.0;

  final AiSource selected;
  final ValueChanged<AiSource> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    Widget tab(AiSource source, String text) {
      final on = source == selected;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          inMutuallyExclusiveGroup: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.full),
            onTap: on ? null : () => onSelect(source),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.sheet : null,
                borderRadius: BorderRadius.circular(Radii.full),
                border: on
                    ? Border.all(color: c.ink, width: Layout.outline)
                    : null,
              ),
              child: Text(
                text,
                style: StabiloType.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: on ? c.ink : c.ink2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: _track,
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        spacing: Space.s1,
        children: [
          tab(AiSource.subsidy, l.aiSourceFree),
          tab(AiSource.own, l.aiSourceOwn),
        ],
      ),
    );
  }
}

/// Kartu tiga model gratis, satu radio per baris (board 03).
class _FreeModelList extends StatelessWidget {
  const _FreeModelList({
    required this.ids,
    required this.current,
    required this.onSelect,
  });

  final List<String> ids;
  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.menu),
        border: Border.all(color: c.menuLine),
      ),
      child: Column(
        children: [
          for (var i = 0; i < ids.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: c.menuLine,
              ),
            _ModelRadio(
              id: ids[i],
              isDefault: ids[i] == defaultAiModel,
              selected: ids[i] == current,
              onTap: () => onSelect(ids[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelRadio extends StatelessWidget {
  const _ModelRadio({
    required this.id,
    required this.isDefault,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final bool isDefault;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: Space.s3,
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
                  border: Border.all(
                    color: selected ? c.ink : c.fieldLine,
                    width: Layout.outline,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.ink,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Row(
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Text(
                            _modelLabel(id),
                            overflow: TextOverflow.ellipsis,
                            style: StabiloType.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (isDefault)
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.muted,
                              borderRadius: BorderRadius.circular(Radii.full),
                            ),
                            child: Text(
                              context.l10n.settingsAiDefaultBadge,
                              style: StabiloType.micro.copyWith(color: c.ink),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      id,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.mono.copyWith(
                        fontSize: 11.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kotak keterangan: ikon + teks di atas chip (board 03 / 04).
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final List<List<dynamic>> icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.s3),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(icon, size: 16, color: c.ink),
          ),
          Expanded(
            child: Text(
              text,
              style: StabiloType.caption.copyWith(
                fontSize: 13,
                height: 1.45,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Key ditolak (board 06). [fallback]: key kesimpen yang ditolak, AI sementara
/// pakai kuota gratis; key baru yang ditolak gak pernah kesimpen.
class _RejectedBox extends ConsumerWidget {
  const _RejectedBox({required this.fallback});

  final bool fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final l = context.l10n;
    final quota = ref.watch(aiQuotaProvider).value;
    final percent = quota != null && quota.usage != null ? quota.percent : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.s3),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.field),
        border: Border.all(color: c.danger, width: Layout.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.s1,
        children: [
          Text(
            l.settingsAiKeyRejectedBody,
            style: StabiloType.caption.copyWith(
              fontSize: 13.5,
              height: 1.45,
              color: c.ink,
            ),
          ),
          if (fallback)
            Text(
              percent == null
                  ? l.settingsAiKeyRejectedFallbackNoQuota
                  : l.settingsAiKeyRejectedFallback(percent),
              style: StabiloType.caption.copyWith(
                fontSize: 12.5,
                height: 1.4,
                color: c.ink2,
              ),
            ),
        ],
      ),
    );
  }
}

/// Status key sendiri (board 04–06): lagi dicek, jalan, ditolak.
class _KeyStatusRow extends StatelessWidget {
  const _KeyStatusRow({required this.status, required this.onRecheck});

  final KeyStatus status;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final small = StabiloType.caption.copyWith(fontSize: 12.5, color: c.ink2);
    final strong = StabiloType.caption.copyWith(fontWeight: FontWeight.w700);
    Widget danger(String text) =>
        Text(text, style: strong.copyWith(color: c.danger));
    final content = switch (status) {
      KeyStatus.idle => Text(
        l.settingsStoredSecurelyOnYourDeviceKeychain,
        style: small,
      ),
      KeyStatus.checking => Row(
        spacing: Space.s2,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: c.ink,
              backgroundColor: c.track,
            ),
          ),
          Flexible(child: Text(l.settingsAiKeyChecking, style: strong)),
        ],
      ),
      KeyStatus.badFormat => danger(l.settingsThatSNotAnOpenrouterApi),
      KeyStatus.refused => Row(
        spacing: 6,
        children: [
          AppIcon(AppIcons.alert, size: 16, color: c.danger),
          Expanded(child: danger(l.settingsOpenrouterRejectedTheKeySoIt)),
        ],
      ),
      KeyStatus.rejected => Row(
        spacing: 6,
        children: [
          AppIcon(AppIcons.alert, size: 16, color: c.danger),
          Flexible(child: danger(l.aiKeyRejected401)),
        ],
      ),
      KeyStatus.valid => Row(
        spacing: 6,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
            child: AppIcon(AppIcons.check, size: 11, color: c.sheet),
          ),
          Text(l.settingsYourKeyWorks, style: strong.copyWith(color: c.ink)),
        ],
      ),
    };
    final trailing = switch (status) {
      KeyStatus.valid => Text(l.aiCheckedJustNow, style: small),
      KeyStatus.rejected || KeyStatus.refused => InkWell(
        onTap: onRecheck,
        child: Text(
          l.settingsAiKeyRecheck,
          style: strong.copyWith(
            fontSize: 12.5,
            decoration: TextDecoration.underline,
            color: c.ink,
          ),
        ),
      ),
      _ => null,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: content),
          ?trailing,
        ],
      ),
    );
  }
}

/// Model buat key sendiri: buka pemilih katalog (board 04–06).
class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.id,
    required this.subtitle,
    required this.onTap,
  });

  final String id;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Material(
      color: c.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        side: BorderSide(color: c.menuLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.field),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: Space.s3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      context.l10n.settingsAiModel,
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                    Text(
                      _modelLabel(id),
                      style: StabiloType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: StabiloType.mono.copyWith(
                        fontSize: 11.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon(AppIcons.chevron, size: 16, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

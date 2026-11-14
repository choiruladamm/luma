import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/model_catalog_service.dart';
import '../../../../domain/models/ai_model.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/field.dart';
import '../../../core/widgets/quota.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/ai_quota_view_model.dart';
import '../view_models/settings_view_model.dart';

/// Permintaan "Pakai key sendiri" dari layar kuota abis / dicabut: Pengaturan
/// buka mode Key sendiri dengan field key fokus (board Kuota AI, Aturan).
class OwnKeyRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final ownKeyRequestProvider = NotifierProvider<OwnKeyRequest, int>(
  OwnKeyRequest.new,
);

/// Dari kartu kuota abis / dicabut ke Pengaturan → AI, mode Key sendiri.
/// [closeSheet]: tutup sheet tempat kartunya dulu (Artinya, intip).
void openOwnKeySettings(
  BuildContext context,
  WidgetRef ref, {
  bool closeSheet = false,
}) {
  final router = GoRouter.of(context);
  ref.read(ownKeyRequestProvider.notifier).request();
  if (closeSheet) Navigator.of(context).pop();
  router.push(Routes.settings);
}

String _modelLabel(String id) {
  for (final m in aiModels) {
    if (m.id == id) return m.label;
  }
  return id;
}

/// Pengaturan → AI (board Kuota AI 02–07): sumber AI, key sendiri, model.
class AiSourceSection extends ConsumerStatefulWidget {
  const AiSourceSection({super.key});

  @override
  ConsumerState<AiSourceSection> createState() => _AiSourceSectionState();
}

class _AiSourceSectionState extends ConsumerState<AiSourceSection> {
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
    // Masih ada key kesimpen: balik ke gratis = hapus key (board 05).
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

  Future<void> _pickModel(AiSource source, String current) async {
    final picked = await showModelPickerSheet(
      context,
      source: source,
      current: current,
      onUseOwnKey: () => _openOwnKey(focus: true),
    );
    if (picked != null) {
      await ref.read(settingsRepositoryProvider).saveModel(picked);
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
      // Key dihapus lewat ×: model di luar 3 model gratis bakal ditolak
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
    final c = context.stabilo;
    final l = context.l10n;
    final stored = ref.watch(aiSourceProvider).value ?? AiSource.subsidy;
    final source = _picked ?? stored;
    final model = ref.watch(aiModelProvider).value ?? defaultAiModel;
    final status = ref.watch(apiKeyEntryProvider);
    final label = StabiloType.caption.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        Text(
          l.aiSection.toUpperCase(),
          style: label.copyWith(letterSpacing: 0.6),
        ),
        Text(l.quotaSource, style: label),
        _SourceTabs(
          selected: source,
          onSelect: (s) => _selectSource(s, stored),
        ),
        if (source == AiSource.own) ...[
          AppField(
            label: l.settingsOpenrouterApiKey,
            controller: _key,
            focusNode: _focus,
            hint: 'sk-or-v1-…',
            secret: true,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
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
          OwnKeyStatus(status: status),
          if (status == KeyStatus.rejected || status == KeyStatus.refused)
            _NoteBox(text: l.aiKeyRejectedBox, danger: true)
          else
            _NoteBox(text: l.aiOwnKeyCost),
        ],
        _ModelRow(
          id: model,
          isDefault: model == defaultAiModel,
          onTap: () => _pickModel(source, model),
        ),
        if (source == AiSource.own && stored == AiSource.own)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _backToFree,
              child: Text(
                l.aiBackToFree,
                style: StabiloType.label.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  color: c.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SourceTabs extends StatelessWidget {
  const _SourceTabs({required this.selected, required this.onSelect});

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
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.sheet : null,
                borderRadius: BorderRadius.circular(Radii.full),
                border: on ? Border.all(color: c.ink, width: 1.5) : null,
              ),
              child: Text(
                text,
                style: StabiloType.label.copyWith(
                  fontWeight: FontWeight.w700,
                  color: on ? c.ink : c.ink2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 46,
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

/// Status key sendiri (board Kuota AI 03–04).
class OwnKeyStatus extends StatelessWidget {
  const OwnKeyStatus({super.key, required this.status});

  final KeyStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final small = StabiloType.caption.copyWith(fontSize: 12.5, color: c.ink2);
    final strong = StabiloType.caption.copyWith(fontWeight: FontWeight.w700);
    return switch (status) {
      KeyStatus.idle => Text(
        l.settingsStoredSecurelyOnYourDeviceKeychain,
        style: small,
      ),
      KeyStatus.checking => Text(l.settingsHangOnChecking, style: small),
      KeyStatus.badFormat => Text(
        l.settingsThatSNotAnOpenrouterApi,
        style: strong.copyWith(color: c.danger),
      ),
      // Key baru ditolak: gak disimpen, key lama tetap.
      KeyStatus.refused => Text(
        l.settingsOpenrouterRejectedTheKeySoIt,
        style: strong.copyWith(color: c.danger),
      ),
      KeyStatus.rejected => Text(
        l.aiKeyRejected401,
        style: strong.copyWith(color: c.danger),
      ),
      KeyStatus.valid => Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
            child: AppIcon(AppIcons.check, size: 11, color: c.sheet),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l.settingsYourKeyWorks,
              style: strong.copyWith(color: c.ink),
            ),
          ),
          Text(l.aiCheckedJustNow, style: small),
        ],
      ),
    };
  }
}

class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.s3),
      decoration: BoxDecoration(
        color: danger ? c.dangerSoft : c.muted,
        borderRadius: BorderRadius.circular(Radii.field),
      ),
      child: Text(
        text,
        style: StabiloType.caption.copyWith(
          fontSize: 13,
          height: 1.45,
          color: danger ? c.dangerInk : c.ink,
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.id,
    required this.isDefault,
    required this.onTap,
  });

  final String id;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    return Material(
      color: c.sheet,
      borderRadius: BorderRadius.circular(Radii.field),
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
                      l.settingsAiModel,
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.ink2,
                      ),
                    ),
                    Text(
                      _modelLabel(id),
                      style: StabiloType.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      isDefault ? '$id · ${l.aiDefaultTag}' : id,
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

/// Board Kuota AI 05. `true` = balik ke gratis.
Future<bool> showBackToFreeSheet(BuildContext context) async {
  final l = context.l10n;
  final ok = await showAppSheet<bool>(
    context,
    builder: (context) => SheetFrame(
      title: l.aiBackToFreeTitle,
      actions: [
        AppButton.secondary(
          label: l.dialogCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: l.aiBackToFreeConfirm,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      children: [
        Text(
          l.aiBackToFreeBody(_modelLabel(defaultAiModel)),
          style: StabiloType.body.copyWith(color: context.stabilo.ink2),
        ),
        const SizedBox(height: Space.s4),
        const _SheetQuotaMeter(),
      ],
    ),
  );
  return ok ?? false;
}

class _SheetQuotaMeter extends ConsumerWidget {
  const _SheetQuotaMeter();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      QuotaMeter(data: quotaMeterData(ref, source: AiSource.subsidy));
}

/// Isi meter kuota dari provider (dipakai pelat Ex libris + sheet).
QuotaMeterData quotaMeterData(WidgetRef ref, {required AiSource source}) {
  if (source == AiSource.own) return const QuotaMeterOwnKey();
  final quota = ref.watch(aiQuotaProvider);
  final now = ref.read(quotaClockProvider)();
  return switch (quota) {
    AsyncData(value: final q) when q.banned => const QuotaMeterRevoked(),
    AsyncData(value: final q) when q.usage != null => QuotaMeterValue(
      percent: q.percent,
      segments: q.segments,
      tapsLeft: q.tapsLeft,
      resetsAt: q.usage!.resetsAt.toLocal(),
      now: now,
    ),
    AsyncError() => QuotaMeterFailed(
      () => ref.read(aiQuotaProvider.notifier).refresh(force: true),
    ),
    _ => const QuotaMeterLoading(),
  };
}

/// Board Kuota AI 06–07. Hasil = id model yang dipilih.
Future<String?> showModelPickerSheet(
  BuildContext context, {
  required AiSource source,
  required String current,
  required VoidCallback onUseOwnKey,
}) => showAppSheet<String>(
  context,
  maxHeight: 0.85,
  builder: (context) => source == AiSource.subsidy
      ? _FreeModelPicker(current: current, onUseOwnKey: onUseOwnKey)
      : _OwnModelPicker(current: current),
);

class _FreeModelPicker extends ConsumerWidget {
  const _FreeModelPicker({required this.current, required this.onUseOwnKey});

  final String current;
  final VoidCallback onUseOwnKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final l = context.l10n;
    final ids = ref.watch(subsidyModelsProvider).value ?? subsidyModelIds;
    return SheetFrame(
      title: l.aiPickModel,
      children: [
        Text(
          l.aiFreeModelsNote,
          style: StabiloType.caption.copyWith(color: c.ink2),
        ),
        const SizedBox(height: Space.s3),
        for (final id in ids)
          _ModelOption(
            title: _modelLabel(id),
            subtitle: id,
            note: id == defaultAiModel ? l.aiDefaultCheapest : null,
            selected: id == current,
            onTap: () => Navigator.of(context).pop(id),
          ),
        const SizedBox(height: Space.s3),
        Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.field),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s2,
            children: [
              Text(
                l.aiMoreModelsTitle,
                style: StabiloType.titleXs.copyWith(color: c.ink),
              ),
              Text(
                l.aiMoreModelsBody,
                style: StabiloType.caption.copyWith(color: c.ink2),
              ),
              AppButton.secondary(
                label: l.quotaUseOwnKey,
                icon: AppIcons.key,
                onPressed: () {
                  Navigator.of(context).pop();
                  onUseOwnKey();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnModelPicker extends ConsumerStatefulWidget {
  const _OwnModelPicker({required this.current});

  final String current;

  @override
  ConsumerState<_OwnModelPicker> createState() => _OwnModelPickerState();
}

class _OwnModelPickerState extends ConsumerState<_OwnModelPicker> {
  String _query = '';
  CatalogFilter _filter = CatalogFilter.all;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final catalog = ref.watch(modelCatalogProvider);
    final models = catalog.value ?? const <CatalogModel>[];
    final hits = filterCatalog(models, query: _query, filter: _filter);
    return SheetFrame(
      title: l.aiPickModel,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: l.aiSearchModels(models.length),
            prefixIcon: AppIcon(AppIcons.search, size: 18, color: c.ink3),
          ),
          onChanged: (q) => setState(() => _query = q),
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          children: [
            for (final (f, text) in [
              (CatalogFilter.all, l.aiFilterAll),
              (CatalogFilter.cheap, l.aiFilterCheap),
              (CatalogFilter.longContext, l.aiFilterLong),
            ])
              ChoiceChip(
                label: Text(text),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: Space.s2),
        if (catalog.hasError)
          Column(
            spacing: Space.s2,
            children: [
              Text(
                l.aiModelsLoadFailed,
                style: StabiloType.caption.copyWith(color: c.ink2),
              ),
              TextButton(
                onPressed: () => ref.invalidate(modelCatalogProvider),
                child: Text(l.authTryAgain),
              ),
            ],
          )
        else if (catalog.isLoading)
          const Padding(
            padding: EdgeInsets.all(Space.s6),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (hits.isEmpty)
          Text(
            l.aiNoModelMatch,
            style: StabiloType.caption.copyWith(color: c.ink2),
          )
        else
          for (final m in hits.take(80))
            _ModelOption(
              title: m.label,
              subtitle: m.id,
              tag: m.cheap ? l.aiFilterCheap : null,
              selected: m.id == widget.current,
              onTap: () => Navigator.of(context).pop(m.id),
            ),
      ],
    );
  }
}

class _ModelOption extends StatelessWidget {
  const _ModelOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.note,
    this.tag,
  });

  final String title;
  final String subtitle;
  final String? note;
  final String? tag;
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
        borderRadius: BorderRadius.circular(Radii.field),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
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
                  spacing: 1,
                  children: [
                    Row(
                      spacing: Space.s2,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: StabiloType.label.copyWith(
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (tag != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.muted,
                              borderRadius: BorderRadius.circular(Radii.full),
                            ),
                            child: Text(
                              tag!,
                              style: StabiloType.micro.copyWith(color: c.ink),
                            ),
                          ),
                      ],
                    ),
                    if (note != null)
                      Text(
                        note!,
                        style: StabiloType.caption.copyWith(color: c.ink2),
                      ),
                    Text(
                      subtitle,
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

/// Meter kuota di bawah pelat Ex libris (board Kuota AI 01 / Akun 08). Buka
/// Pengaturan = cek kuota, paling sering sejam sekali (cache provider).
class AccountQuotaMeter extends ConsumerStatefulWidget {
  const AccountQuotaMeter({super.key, this.bare = false});

  /// Tanpa kotak sendiri: udah di dalam pelat Ex libris (board Kuota AI 02).
  final bool bare;

  @override
  ConsumerState<AccountQuotaMeter> createState() => _AccountQuotaMeterState();
}

class _AccountQuotaMeterState extends ConsumerState<AccountQuotaMeter> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(aiQuotaProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final source = ref.watch(aiSourceProvider).value ?? AiSource.subsidy;
    final meter = QuotaMeter(data: quotaMeterData(ref, source: source));
    if (widget.bare) return meter;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.s3),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.field),
        border: Border.all(color: c.outline),
      ),
      child: meter,
    );
  }
}

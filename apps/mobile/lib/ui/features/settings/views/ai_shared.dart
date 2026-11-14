import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../../data/services/model_catalog_service.dart';
import '../../../../domain/models/ai_model.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/quota.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/ai_quota_view_model.dart';

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
  router.push(Routes.settingsAi);
}

String _modelLabel(String id) {
  for (final m in aiModels) {
    if (m.id == id) return m.label;
  }
  return id;
}

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

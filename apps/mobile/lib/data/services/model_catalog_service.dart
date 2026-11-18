import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'http_client.dart';

/// Represents one OpenRouter model in the own-key model picker (board Kuota AI 07).
class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.name,
    required this.contextLength,
    required this.promptUsdPerToken,
    required this.completionUsdPerToken,
  });

  factory CatalogModel.fromJson(Map<String, Object?> json) {
    final pricing = json['pricing'];
    double price(String key) =>
        double.tryParse('${pricing is Map ? pricing[key] : null}') ?? 0;
    return CatalogModel(
      id: json['id']! as String,
      name: (json['name'] as String?) ?? json['id']! as String,
      contextLength: (json['context_length'] as num?)?.toInt() ?? 0,
      promptUsdPerToken: price('prompt'),
      completionUsdPerToken: price('completion'),
    );
  }

  final String id;
  final String name;
  final int contextLength;
  final double promptUsdPerToken;
  final double completionUsdPerToken;

  /// Whether the model is "Hemat" (cheap): input ≤ $0.30 per 1M tokens and output ≤ $1.50 per 1M.
  bool get cheap =>
      promptUsdPerToken <= 0.30 / 1e6 && completionUsdPerToken <= 1.50 / 1e6;

  /// Whether the model is "Konteks panjang" (long context): at least 128K tokens.
  bool get longContext => contextLength >= 128000;

  /// Returns the name without the provider prefix ("Google: Gemini 3 Flash" becomes "Gemini 3 Flash").
  String get label {
    final i = name.indexOf(': ');
    return i < 0 ? name : name.substring(i + 2);
  }
}

/// Fetches OpenRouter's public model list (`GET /api/v1/models`, no key needed).
///
/// Called only when the own-key model picker opens; the result is reused for
/// the rest of the app session.
class ModelCatalogService {
  ModelCatalogService([Dio? dio]) : _dio = dio ?? lumaDio();

  final Dio _dio;

  Future<List<CatalogModel>> models() async {
    final res = await _dio.get<Map<String, Object?>>(
      'https://openrouter.ai/api/v1/models',
    );
    final rows = res.data?['data'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map<String, Object?> && row['id'] is String)
          CatalogModel.fromJson(row),
    ];
  }
}

final modelCatalogServiceProvider = Provider<ModelCatalogService>(
  (ref) => ModelCatalogService(),
);

final modelCatalogProvider = FutureProvider<List<CatalogModel>>(
  (ref) => ref.watch(modelCatalogServiceProvider).models(),
);

enum CatalogFilter { all, cheap, longContext }

/// Filters and searches [models], listing cheap models first.
List<CatalogModel> filterCatalog(
  List<CatalogModel> models, {
  String query = '',
  CatalogFilter filter = CatalogFilter.all,
}) {
  final q = query.trim().toLowerCase();
  final hits = models.where((m) {
    final matches =
        q.isEmpty ||
        m.id.toLowerCase().contains(q) ||
        m.name.toLowerCase().contains(q);
    return matches &&
        switch (filter) {
          CatalogFilter.all => true,
          CatalogFilter.cheap => m.cheap,
          CatalogFilter.longContext => m.longContext,
        };
  }).toList();
  hits.sort((a, b) {
    if (a.cheap != b.cheap) return a.cheap ? -1 : 1;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return hits;
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/book_source.dart';
import 'package:luma/data/services/catalog_sync_service.dart';
import 'package:luma/domain/models/catalog.dart';
import 'package:luma/ui/features/discover/view_models/discover_view_model.dart';

import 'discover_view_test.dart' show FakeSource, FakeSync, book;

void main() {
  late FakeSource source;
  late ProviderContainer container;
  late ProviderSubscription<DiscoverState> sub;

  setUp(() {
    source = FakeSource();
    container = ProviderContainer(
      overrides: [
        bookSourcesProvider.overrideWithValue([source]),
        catalogSyncProvider.overrideWith(FakeSync.new),
      ],
    );
    sub = container.listen(discoverProvider, (_, _) {});
  });
  tearDown(() {
    sub.close();
    container.dispose();
  });

  DiscoverState state() => container.read(discoverProvider);

  test('popular: loading → ready (top 10)', () async {
    await Future<void>.delayed(Duration.zero);
    expect(state().popular, isA<PopularLoading>());
    source.popular.complete(
      CatalogPage(
        items: [for (var i = 1; i <= 25; i++) book(i, 'B$i')],
        hasMore: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final ready = state().popular as PopularReady;
    expect(ready.items, hasLength(10));
  });

  test('popular: offline vs dead', () async {
    await Future<void>.delayed(Duration.zero);
    source.popular.completeError(
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect((state().popular as PopularFailed).failure, NetworkFailure.offline);
    source.popular = Completer();
    unawaited(container.read(discoverProvider.notifier).loadPopular());
    source.popular.completeError(Exception('503'));
    await Future<void>.delayed(Duration.zero);
    expect((state().popular as PopularFailed).failure, NetworkFailure.dead);
  });

  test('query: results, stale answers dropped, clear resets', () async {
    source.catalog.addAll([book(1, 'Emma'), book(2, 'Persuasion')]);
    final vm = container.read(discoverProvider.notifier);
    unawaited(vm.setQuery('em'));
    unawaited(vm.setQuery('pers'));
    await Future<void>.delayed(Duration.zero);
    expect(state().results!.items.single.title, 'Persuasion');
    expect(state().results!.total, 1);
    await vm.setQuery('');
    expect(state().results, isNull);
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/book_search_index.dart';
import 'package:luma/data/repositories/book_search_repository.dart';
import 'package:luma/ui/features/reader/view_models/book_search_view_model.dart';

import '../../../fakes.dart';

void main() {
  late FakeBookSearch repo;
  late FakeSearchIndex index;

  final netherfield = fakeResult([
    (
      1,
      'Chapter I',
      [
        fakeHit(
          1,
          0,
          'heard that Netherfield Park is let',
          match: 'Netherfield',
        ),
      ],
    ),
  ]);

  /// Runs [body] in a fake clock with the VM alive and past its first load.
  void run(
    void Function(
      FakeAsync async,
      ProviderContainer c,
      BookSearchState Function() state,
      BookSearchViewModel vm,
    )
    body,
  ) {
    fakeAsync((async) {
      final c = ProviderContainer(
        overrides: [
          bookSearchRepositoryProvider.overrideWithValue(repo),
          bookSearchIndexProvider.overrideWithValue(index),
        ],
      );
      c.listen(bookSearchProvider(7), (_, _) {});
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      body(
        async,
        c,
        () => c.read(bookSearchProvider(7)),
        c.read(bookSearchProvider(7).notifier),
      );
      c.dispose();
    });
  }

  setUp(() {
    repo = FakeBookSearch(
      results: {'netherfield': netherfield},
      recents: ['Mr. Darcy', 'entailed'],
    );
    index = FakeSearchIndex();
  });

  test('indexed book opens on the recents', () {
    run((async, c, state, vm) {
      expect(state().phase, BookSearchPhase.idle);
      expect(state().recents, ['Mr. Darcy', 'entailed']);
    });
  });

  test('an unindexed book shows progress, then opens', () {
    index = FakeSearchIndex(indexed: false, chapters: 4, hold: true);
    run((async, c, state, vm) {
      expect(state().phase, BookSearchPhase.preparing);
      expect((state().doneChapters, state().totalChapters), (2, 4));
      expect(state().prepareFraction, 0.5);
      index.release();
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.idle);
      expect(index.indexed, isTrue);
    });
  });

  test('a query typed while preparing is searched once ready', () {
    index = FakeSearchIndex(indexed: false, hold: true);
    run((async, c, state, vm) {
      vm.setQuery('Netherfield');
      async.elapse(VmDebounce.value * 2);
      expect(repo.searches, isEmpty);
      index.release();
      async.flushMicrotasks();
      expect(repo.searches, ['Netherfield']);
      expect(state().phase, BookSearchPhase.results);
    });
  });

  test('searches 250 ms after the last keystroke, not before', () {
    run((async, c, state, vm) {
      vm.setQuery('Neth');
      async.elapse(const Duration(milliseconds: 200));
      vm.setQuery('Netherfield');
      async.elapse(const Duration(milliseconds: 249));
      expect(repo.searches, isEmpty);
      expect(state().phase, BookSearchPhase.idle);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repo.searches, ['Netherfield']); // 'Neth' never ran
      expect(state().phase, BookSearchPhase.results);
      expect(state().result.total, 1);
    });
  });

  test('under 2 letters goes back to the recents, nothing searched', () {
    run((async, c, state, vm) {
      vm.setQuery('Netherfield');
      async.elapse(VmDebounce.value);
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.results);
      vm.setQuery('N');
      async.elapse(VmDebounce.value * 2);
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.idle);
      expect(state().result.isEmpty, isTrue);
      expect(repo.searches, ['Netherfield']);
    });
  });

  test('no match is the empty phase', () {
    run((async, c, state, vm) {
      vm.setQuery('Netherfeild');
      async.elapse(VmDebounce.value);
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.empty);
      expect(state().query, 'Netherfeild');
    });
  });

  test('a slow older search never overwrites a newer one', () {
    repo.slowFirst = true;
    run((async, c, state, vm) {
      vm.setQuery('netherfield');
      async.elapse(VmDebounce.value);
      vm.setQuery('zzzz');
      async.elapse(VmDebounce.value);
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.empty);
      repo.releaseFirst();
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.empty); // not the stale hit
      expect(repo.searches, ['netherfield', 'zzzz']); // the old one did run
    });
  });

  test('tapping a recent searches right away', () {
    run((async, c, state, vm) {
      vm.searchNow('Netherfield');
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.results);
      expect(state().query, 'Netherfield');
    });
  });

  test('remember saves the query and refreshes the recents', () {
    run((async, c, state, vm) {
      vm.setQuery('  Netherfield ');
      async.elapse(VmDebounce.value);
      async.flushMicrotasks();
      vm.remember();
      async.flushMicrotasks();
      expect(state().recents.first, 'Netherfield');
      expect(repo.recents, ['Netherfield', 'Mr. Darcy', 'entailed']);
    });
  });

  test('clearRecents empties them', () {
    run((async, c, state, vm) {
      vm.clearRecents();
      async.flushMicrotasks();
      expect(state().recents, isEmpty);
      expect(repo.recents, isEmpty);
    });
  });

  test('a throwing search is the failed phase', () {
    repo.failWith = StateError('boom');
    run((async, c, state, vm) {
      vm.setQuery('Netherfield');
      async.elapse(VmDebounce.value);
      async.flushMicrotasks();
      expect(state().phase, BookSearchPhase.failed);
    });
  });
}

class VmDebounce {
  static const value = BookSearchViewModel.debounce;
}

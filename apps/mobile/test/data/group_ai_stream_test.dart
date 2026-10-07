import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/ai_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';

import '../fakes.dart';

/// `ai_results` without a database: [saved] is the cache.
class FakeCache implements AiResultsRepository {
  final saved = <GroupRef, AiReply>{};
  final opened = <GroupRef>[];

  @override
  Future<AiReply?> find(GroupRef group) async => saved[group];

  @override
  Future<void> markOpened(GroupRef group) async => opened.add(group);

  @override
  Future<void> save(
    GroupRef group,
    AiReply reply, {
    required String model,
  }) async => saved[group] = reply;

  @override
  Future<({AiBook? book, List<String> target, List<String> context})>
  promptText(GroupRef group, {int contextCount = 3}) async => (
    book: (title: 'Meditations', author: 'Marcus Aurelius', chapter: 'II'),
    target: ['Hello there.', 'Bye.'],
    context: ['Before.'],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const group = (chapterId: 1, groupIndex: 0);
  late FakeOpenRouter ai;
  late FakeCache cache;
  late ProviderContainer container;
  late List<AiStream> states;
  late ProviderSubscription<AiStream> sub;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'openrouter_api_key': 'sk'});
    ai = FakeOpenRouter();
    cache = FakeCache();
    container = ProviderContainer(
      overrides: [
        aiResultsRepositoryProvider.overrideWithValue(cache),
        openRouterServiceProvider.overrideWithValue(ai),
        settingsRepositoryProvider.overrideWithValue(FakeSettings()),
      ],
    );
    states = [];
  });

  tearDown(() => container.dispose());

  /// Opens the sheet: listens like the sheet does, lets the setup run.
  void open(FakeAsync async) {
    sub = container.listen(
      groupAiStreamProvider(group),
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    async.flushMicrotasks();
  }

  AiStream now() => container.read(groupAiStreamProvider(group));
  List<AiPhase> phases() => [for (final s in states) s.phase];

  test('a cached group is done at once, nothing streamed', () {
    fakeAsync((async) {
      cache.saved[group] = const AiReply(
        translations: ['A', 'B'],
        meaning: 'M',
      );
      open(async);
      expect(now().phase, AiPhase.done);
      expect(now().cached, isTrue);
      expect(now().draft.translations, ['A', 'B']);
      expect(ai.streamCalls, isEmpty);
      expect(cache.opened, [group]); // re-read counts
    });
  });

  test('waiting → translating → meaning → done, then cached', () {
    fakeAsync((async) {
      final c = ai.stream = StreamController<String>();
      open(async);
      expect(now().phase, AiPhase.waiting);
      expect(now().sources, [12, 4]); // placeholder sizes from the original
      expect(
        ai.streamBooks.single?.title,
        'Meditations',
      ); // the book rides along

      c.add('[T1]\nHalo ');
      async.flushMicrotasks();
      expect(now().phase, AiPhase.translating);
      expect(now().draft.translations, ['Halo']);

      c.add('juga.\n[T2]\nDah.\n[MAK');
      async.flushMicrotasks();
      expect(now().draft.translations, ['Halo juga.', 'Dah.']);
      expect(now().phase, AiPhase.translating); // marker not complete yet

      c.add('NA]\nGitu.');
      async.flushMicrotasks();
      expect(now().phase, AiPhase.meaning);
      expect(cache.saved, isEmpty); // nothing half-done is saved

      unawaited(c.close());
      async.flushMicrotasks();
      expect(now().phase, AiPhase.done);
      expect(cache.opened, isEmpty); // saving is the first open, not another
      expect(now().draft.meaning, 'Gitu.');
      expect(cache.saved[group]!.translations, ['Halo juga.', 'Dah.']);
      expect(phases().first, AiPhase.waiting);
      // Nothing left ticking once done.
      async.elapse(const Duration(minutes: 1));
      expect(now().phase, AiPhase.done);
    });
  });

  test('15 s without a token is slow; a late token goes on writing', () {
    fakeAsync((async) {
      final c = ai.stream = StreamController<String>();
      open(async);
      async.elapse(const Duration(seconds: 15));
      expect(now().phase, AiPhase.slow);
      c.add('[T1]\nHalo');
      async.flushMicrotasks();
      expect(now().phase, AiPhase.translating);
      // The 30 s timeout no longer applies once tokens flow.
      async.elapse(const Duration(seconds: 16));
      expect(now().phase, isNot(AiPhase.failed));
    });
  });

  test('30 s without a token fails as timeout and cancels', () {
    fakeAsync((async) {
      ai.stream = StreamController<String>();
      open(async);
      async.elapse(const Duration(seconds: 30));
      expect(now().phase, AiPhase.failed);
      expect(now().error?.error, AiError.timeout);
      expect(ai.lastCancel!.isCancelled, isTrue);
      expect(cache.saved, isEmpty);
    });
  });

  test('tokens stopping for 20 s mid-answer is cut, text kept', () {
    fakeAsync((async) {
      final c = ai.stream = StreamController<String>();
      open(async);
      c.add('[T1]\nHalo juga.\n[T2]\nDa');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 19));
      expect(now().phase, AiPhase.translating);
      async.elapse(const Duration(seconds: 1));
      expect(now().phase, AiPhase.cut);
      expect(now().draft.translations, ['Halo juga.', 'Da']);
      expect(ai.lastCancel!.isCancelled, isTrue);
      expect(cache.saved, isEmpty);
    });
  });

  test('the connection dropping mid-answer is cut', () {
    fakeAsync((async) {
      final c = ai.stream = StreamController<String>();
      open(async);
      c
        ..add('[T1]\nHalo')
        ..addError(const AiException(AiError.network));
      async.flushMicrotasks();
      expect(now().phase, AiPhase.cut);
      expect(now().draft.translations, ['Halo']);
      expect(cache.saved, isEmpty);
    });
  });

  test('failing before any token is an error, not cut', () {
    fakeAsync((async) {
      ai.failure = const AiException(AiError.http, status: 402);
      open(async);
      expect(now().phase, AiPhase.failed);
      expect(now().error?.status, 402);
    });
  });

  test('an invalid answer is asked once more without streaming', () {
    fakeAsync((async) {
      final c = ai.stream = StreamController<String>();
      open(async);
      c.add('[T1]\nCuma satu.\n[MAKNA]\nM.'); // 1 of 2 paragraphs
      unawaited(c.close());
      async.flushMicrotasks();
      expect(now().phase, AiPhase.done);
      expect(ai.calls, hasLength(1)); // the JSON path, once
      expect(now().draft.translations, ['id: Hello there.', 'id: Bye.']);
      expect(cache.saved[group]!.translations, hasLength(2));
    });
  });

  test('closing the sheet cancels; nothing is saved', () {
    fakeAsync((async) {
      final c = ai.stream = StreamController<String>();
      open(async);
      c.add('[T1]\nHalo');
      async.flushMicrotasks();
      sub.close();
      async.elapse(Duration.zero); // autoDispose runs on the next tick
      expect(ai.lastCancel!.isCancelled, isTrue);
      unawaited(c.close());
      async.elapse(const Duration(minutes: 1));
      expect(cache.saved, isEmpty);
    });
  });

  test(
    'closing the sheet mid-answer: the cancel error is not read as state',
    () {
      fakeAsync((async) {
        final c = ai.stream = StreamController<String>();
        open(async);
        c.add('[T1]\nHalo');
        async.flushMicrotasks();
        sub.close();
        async.elapse(Duration.zero);
        // What the cancelled request throws once the provider is gone.
        c.addError(const AiException(AiError.network));
        async.flushMicrotasks(); // would throw "Ref ... after it has been disposed"
        expect(cache.saved, isEmpty);
      });
    },
  );

  test('no API key: fails without streaming anything', () {
    fakeAsync((async) {
      FlutterSecureStorage.setMockInitialValues({});
      open(async);
      expect(now().phase, AiPhase.failed);
      expect(now().error?.error, AiError.noApiKey);
    });
  });

  test('retry starts over from waiting with a new request', () {
    fakeAsync((async) {
      final c = ai.stream = StreamController<String>.broadcast();
      open(async);
      c
        ..add('[T1]\nHalo')
        ..addError(const AiException(AiError.network));
      async.flushMicrotasks();
      expect(now().phase, AiPhase.cut);

      container.invalidate(groupAiStreamProvider(group));
      async.elapse(Duration.zero);
      expect(now().phase, AiPhase.waiting);
      expect(now().draft.translations, isEmpty);
      expect(ai.streamCalls, hasLength(2));
    });
  });

  test('two listeners share one request', () {
    fakeAsync((async) {
      ai.stream = StreamController<String>();
      open(async);
      final other = container.listen(groupAiStreamProvider(group), (_, _) {});
      async.flushMicrotasks();
      expect(ai.streamCalls, hasLength(1));
      other.close();
    });
  });
}

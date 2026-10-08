import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_breakdowns_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/breakdown_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/breakdown.dart';
import 'package:luma/ui/features/reader/view_models/breakdown_view_model.dart';

import '../fakes.dart';

/// `ai_breakdowns` without a database: [saved] is the cache, keyed by the
/// translation hash it was made for.
class FakeBreakdowns implements AiBreakdownsRepository {
  final saved = <GroupRef, ({String body, String hash})>{};
  List<String> translations = ['Satu. Dua.', 'Tiga.']; // K1-K3
  bool translated = true;

  BreakdownInput get _input => BreakdownInput(
    book: (title: 'The Enchiridion', author: 'Epictetus', chapter: 'V'),
    chapters: const ['I', 'V'],
    chapter: 2,
    original: const ['One. Two.', 'Three.'],
    translations: translations,
    meaning: 'M',
  );

  @override
  Future<BreakdownInput?> input(GroupRef group) async =>
      translated ? _input : null;

  @override
  Future<String?> find(GroupRef group, String sourceHash) async =>
      saved[group]?.hash == sourceHash ? saved[group]!.body : null;

  @override
  Future<bool> exists(GroupRef group) async =>
      saved[group]?.hash == breakdownSourceHash(translations);

  @override
  Future<void> save(
    GroupRef group, {
    required String body,
    required String sourceHash,
    required String model,
  }) async => saved[group] = (body: body, hash: sourceHash);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const answer =
    '[BAGIAN K1-K2]\nJudul: A\nMaksudnya: MA\nLogikanya: LA\n'
    '[BAGIAN K3-K3]\nJudul: B\nMaksudnya: MB\nLogikanya: LB';

void main() {
  const group = (chapterId: 1, groupIndex: 0);
  late FakeOpenRouter ai;
  late FakeBreakdowns repo;
  late ProviderContainer container;
  late ProviderSubscription<BreakdownState> sub;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'openrouter_api_key': 'sk'});
    ai = FakeOpenRouter();
    repo = FakeBreakdowns();
    container = ProviderContainer(
      overrides: [
        aiBreakdownsRepositoryProvider.overrideWithValue(repo),
        openRouterServiceProvider.overrideWithValue(ai),
        settingsRepositoryProvider.overrideWithValue(FakeSettings()),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// Opens the Bedahin screen: listens like the screen does.
  void open(FakeAsync async) {
    sub = container.listen(breakdownStreamProvider(group), (_, _) {});
    async.flushMicrotasks();
  }

  BreakdownState now() => container.read(breakdownStreamProvider(group));

  StreamController<String> next() {
    final c = StreamController<String>();
    ai.breakdowns.add(c);
    return c;
  }

  test('a cached breakdown is done at once, nothing streamed', () {
    fakeAsync((async) {
      repo.saved[group] = (
        body: answer,
        hash: breakdownSourceHash(repo.translations),
      );
      open(async);
      expect(now().phase, BreakdownPhase.done);
      expect(now().cached, isTrue);
      expect(now().draft.sections, hasLength(2));
      expect(now().input!.translations, repo.translations);
      expect(ai.breakdownCalls, isEmpty);
    });
  });

  test('changed translation: broken down again', () {
    fakeAsync((async) {
      repo.saved[group] = (body: answer, hash: breakdownSourceHash(['old']));
      open(async);
      expect(now().phase, BreakdownPhase.done);
      expect(now().cached, isFalse);
      expect(ai.breakdownCalls, hasLength(1));
      expect(repo.saved[group]!.hash, breakdownSourceHash(repo.translations));
    });
  });

  test('waiting → writing → done, then cached', () {
    fakeAsync((async) {
      final c = next();
      open(async);
      expect(now().phase, BreakdownPhase.waiting);
      expect(now().input, isNotNull); // the text panel shows right away

      c.add('[BAGIAN K1-K2]\nJudul: A\nMaksud');
      async.flushMicrotasks();
      expect(now().phase, BreakdownPhase.writing);
      expect(
        (now().draft.sections.single.from, now().draft.sections.single.to),
        (1, 2),
      );
      expect(repo.saved, isEmpty);

      c.add(answer.substring('[BAGIAN K1-K2]\nJudul: A\nMaksud'.length));
      unawaited(c.close());
      async.flushMicrotasks();
      expect(now().phase, BreakdownPhase.done);
      expect(now().draft.sections, hasLength(2));
      expect(repo.saved[group]!.body, answer);
      async.elapse(const Duration(minutes: 1)); // nothing left ticking
      expect(now().phase, BreakdownPhase.done);
    });
  });

  test('invalid once: streamed again, then done', () {
    fakeAsync((async) {
      final first = next();
      final second = next();
      open(async);
      first.add('[BAGIAN K1-K2]\nJudul: A\nMaksudnya: M\nLogikanya: L'); // K3?
      unawaited(first.close());
      async.flushMicrotasks();
      expect(now().phase, BreakdownPhase.waiting);
      expect(now().draft.sections, isEmpty);
      expect(ai.breakdownCalls, hasLength(2));

      second.add(answer);
      unawaited(second.close());
      async.flushMicrotasks();
      expect(now().phase, BreakdownPhase.done);
      expect(repo.saved[group]!.body, answer);
    });
  });

  test('invalid twice fails as invalidResponse; nothing saved', () {
    fakeAsync((async) {
      for (final c in [next(), next()]) {
        c.add('Maaf.');
        unawaited(c.close());
      }
      open(async);
      expect(now().phase, BreakdownPhase.failed);
      expect(now().error?.error, AiError.invalidResponse);
      expect(ai.breakdownCalls, hasLength(2));
      expect(repo.saved, isEmpty);
    });
  });

  test('15 s without a token is slow; 30 s fails as timeout', () {
    fakeAsync((async) {
      next();
      open(async);
      async.elapse(const Duration(seconds: 15));
      expect(now().phase, BreakdownPhase.slow);
      async.elapse(const Duration(seconds: 15));
      expect(now().phase, BreakdownPhase.failed);
      expect(now().error?.error, AiError.timeout);
      expect(ai.lastCancel!.isCancelled, isTrue);
    });
  });

  test('tokens stopping for 20 s mid-answer is cut, text kept', () {
    fakeAsync((async) {
      final c = next();
      open(async);
      c.add('[BAGIAN K1-K2]\nJudul: A');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 20));
      expect(now().phase, BreakdownPhase.cut);
      expect(now().draft.sections.single.title, 'A');
      expect(ai.lastCancel!.isCancelled, isTrue);
      expect(repo.saved, isEmpty);
    });
  });

  test('the connection dropping mid-answer is cut', () {
    fakeAsync((async) {
      final c = next();
      open(async);
      c
        ..add('[BAGIAN K1-K2]\nJudul: A')
        ..addError(const AiException(AiError.network));
      async.flushMicrotasks();
      expect(now().phase, BreakdownPhase.cut);
    });
  });

  test('closing the screen cancels; nothing is saved', () {
    fakeAsync((async) {
      final c = next();
      open(async);
      c.add('[BAGIAN K1-K2]\nJudul: A');
      async.flushMicrotasks();
      sub.close();
      async.elapse(Duration.zero); // autoDispose runs on the next tick
      expect(ai.lastCancel!.isCancelled, isTrue);
      c
        ..add(answer)
        ..addError(const AiException(AiError.network));
      async.elapse(const Duration(minutes: 1));
      expect(repo.saved, isEmpty);
    });
  });

  test('no API key, or no quick meaning yet: failed, nothing sent', () {
    fakeAsync((async) {
      FlutterSecureStorage.setMockInitialValues({});
      open(async);
      expect(now().phase, BreakdownPhase.failed);
      expect(now().error?.error, AiError.noApiKey);

      sub.close();
      async.elapse(Duration.zero);
      repo.translated = false;
      open(async);
      expect(now().phase, BreakdownPhase.failed);
      expect(now().input, isNull);
      expect(ai.breakdownCalls, hasLength(1)); // only the no-key attempt
    });
  });

  test('done refreshes the "already broken down" flag', () {
    fakeAsync((async) {
      final exists = container.listen(
        breakdownExistsProvider(group),
        (_, _) {},
      );
      async.flushMicrotasks();
      expect(exists.read().value, isFalse);
      open(async); // default fake answer: one valid section
      async.elapse(Duration.zero);
      expect(now().phase, BreakdownPhase.done);
      expect(exists.read().value, isTrue);
      exists.close();
    });
  });
}

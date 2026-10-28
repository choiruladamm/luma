import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/ui/features/chat/view_models/chat_view_model.dart';

import 'chat_context_repository_test.dart' show ChatAdapter, Keys;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ChatRepository repo;
  late ChatContextRepository context;
  late Keys keys;
  late ChatAdapter adapter;
  late ProviderContainer container;
  late ChatBookRef book;
  late ProviderSubscription<ChatState> subscription;
  const model = 'chosen/model';
  final provider = chatViewModelProvider(1);
  ChatViewModel vm() => container.read(provider.notifier);
  ChatState state() => container.read(provider);
  Future<void> when(bool Function(ChatState) check) async {
    if (check(state())) return;
    final done = Completer<void>();
    final sub = container.listen(provider, (_, next) {
      if (!done.isCompleted && check(next)) done.complete();
    });
    try {
      await done.future.timeout(const Duration(seconds: 3));
    } finally {
      sub.close();
    }
  }

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final id = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'Garden',
            parserVersion: 1,
            totalChars: 100,
          ),
        );
    book = (bookId: id, contentRevision: 1);
    for (var i = 0; i < 2; i++) {
      final chapter = await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: id,
              sortOrder: i,
              title: 'Chapter $i',
              charOffset: 0,
            ),
          );
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapter,
              paragraphIndex: 0,
              groupIndex: const Value(0),
              type: ParagraphType.paragraph,
              content: i == 0
                  ? 'A garden belongs to its keeper.'
                  : 'The keeper plants roses.',
            ),
          );
    }
    await db
        .into(db.settings)
        .insert(SettingsCompanion.insert(key: 'ai.model', value: model));
    repo = ChatRepository(db);
    keys = Keys();
    adapter = ChatAdapter();
    context = ChatContextRepository(
      db,
      repo,
      OpenRouterService(
        Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
          ..httpClientAdapter = adapter,
      ),
      keys,
    );
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        chatContextRepositoryProvider.overrideWithValue(context),
      ],
    );
    subscription = container.listen(provider, (_, _) {}, fireImmediately: true);
    await when((s) => !s.loading);
  });
  tearDown(() async {
    await vm().stop();
    subscription.close();
    container.dispose();
    context.dispose();
    repo.dispose();
    await db.close();
  });

  test('ViewModel exposes durable index progress and ignores late progress after stop', () async {
    final entered = Completer<void>(), release = Completer<void>();
    adapter.onEmbedding = () async {
      adapter.onEmbedding = null;
      entered.complete();
      await release.future;
    };
    vm().setDraft('Siapa?');
    final send = vm().send();
    await entered.future;
    expect(state().indexProgress, (completed: 0, total: 2));
    await vm().stop();
    release.complete();
    await send;
    expect(state().phase, ChatPhase.stopped);
    expect(state().indexProgress, (completed: 0, total: 2));
    expect(await db.select(db.chatVectors).get(), isEmpty);
  });

  test('real Drift + fake Dio: first send, completed sources, append and resume without paid hydration', () async {
    vm().setDraft('Siapa yang punya taman?');
    final first = vm().send();
    final duplicate = vm().send();
    await Future.wait([first, duplicate]);
    await when((s) => s.turns.lastOrNull?.phase == ChatPhase.done);
    expect((await db.select(db.chatSessions).get()).length, 1);
    expect((await db.select(db.chatTurns).get()).length, 1);
    expect(
      state().turns.single.answer!.blocks.single.sources.single.text,
      'A garden belongs to its keeper.',
    );
    final sessionId = state().activeSession!.id;
    vm().setDraft('Dia nanam apa?');
    await vm().send();
    await when(
      (s) => s.turns.length == 2 && s.turns.last.phase == ChatPhase.done,
    );
    final count = adapter.requests.length;
    await vm().newSession();
    expect(state().activeSession, isNull);
    await vm().openSession(sessionId);
    await when((s) => s.turns.length == 2);
    expect(adapter.requests.length, count);
    expect(state().turns.every((t) => t.trustedHistory), true);
  });

  test('no key finalizes failed, settings change waits for explicit retry on same turn', () async {
    keys.key = null;
    vm().setDraft('Siapa?');
    await vm().send();
    expect(adapter.requests, isEmpty);
    expect((await db.select(db.chatTurns).getSingle()).phase, 'failed');
    expect((await db.select(db.chatTurns).getSingle()).error, 'noApiKey');
    keys.key = 'changed-key';
    await when((s) => s.canRetry);
    expect(adapter.requests, isEmpty);
    await vm().retry();
    expect((await db.select(db.chatTurns).get()).length, 1);
    expect((await db.select(db.chatTurns).getSingle()).attempt, 2);
    expect((await db.select(db.chatTurns).getSingle()).phase, 'done');
  });

  test('stop during real retrieval persists stopped and ignores late selection result', () async {
    final selecting = Completer<void>(), release = Completer<void>();
    adapter.onSelect = () async {
      selecting.complete();
      await release.future;
    };
    vm().setDraft('Siapa?');
    final send = vm().send();
    await selecting.future;
    await vm().stop();
    expect((await db.select(db.chatTurns).getSingle()).phase, 'stopped');
    release.complete();
    await send;
    expect(
      adapter.requests.where((r) => r.path == '/chat/completions'),
      hasLength(2),
    );
    expect((await db.select(db.chatTurns).getSingle()).answer, isNull);
  });

  test(
    'hydrate interrupted/corrupt archive and external deletion never send',
    () async {
      final turn = await repo.createFirstTurn(
        book,
        question: 'Old?',
        model: model,
        promptVersion: chatPromptVersion,
      );
      await repo.finalize(
        turn.attemptRef,
        phase: ChatPhase.interrupted,
        draft: '{partial',
      );
      await vm().openSession(turn.sessionId);
      await when((s) => s.turns.isNotEmpty);
      expect(state().turns.single.phase, ChatPhase.interrupted);
      expect(adapter.requests, isEmpty);
      await (db.update(db.chatTurns)..where((t) => t.id.equals(turn.id))).write(
        const ChatTurnsCompanion(answer: Value('{bad')),
      );
      await (db.update(db.chatSessions)
            ..where((s) => s.id.equals(turn.sessionId)))
          .write(const ChatSessionsCompanion(title: Value('')));
      await when((s) => s.activeSession?.invalid == true);
      expect(state().readOnly, true);
      expect(state().problem, contains('rusak'));
      await repo.deleteSession(book.bookId, turn.sessionId);
      await when((s) => s.activeSession == null && !s.changingSession);
      expect(adapter.requests, isEmpty);
    },
  );
  test('provider rebuild resumes last opened completed session without another request', () async {
    vm().setDraft('Siapa?');
    await vm().send();
    await when((s) => s.turns.lastOrNull?.phase == ChatPhase.done);
    final sessionId = state().activeSession!.id;
    final count = adapter.requests.length;
    container.invalidate(provider);
    await when(
      (s) =>
          !s.loading && s.activeSession?.id == sessionId && s.turns.isNotEmpty,
    );
    expect(adapter.requests.length, count);
    expect(state().turns.single.phase, ChatPhase.done);
  });
}

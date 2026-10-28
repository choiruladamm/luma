import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/chat_lifecycle.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/data/services/restore_service.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/ui/features/chat/view_models/chat_view_model.dart';

import 'chat_context_repository_test.dart' show ChatAdapter, Keys;
import 'restore_service_test.dart' show Phone;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production restore provider cancels live retrieval before SQLite swap; colliding IDs cannot receive late writes', () async {
    final source = await Phone.make(), target = await Phone.make();
    await source.addBook('Backup');
    await source.addChats();
    await target.addBook('Current');
    final adapter = ChatAdapter();
    final selecting = Completer<void>(), release = Completer<void>();
    adapter.onSelect = () async {
      selecting.complete();
      await release.future;
    };
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(target.db),
        fileStorageProvider.overrideWithValue(target.storage),
        apiKeyStoreProvider.overrideWithValue(Keys()),
        openRouterServiceProvider.overrideWithValue(
          OpenRouterService(
            Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
              ..httpClientAdapter = adapter,
          ),
        ),
      ],
    );
    final provider = chatViewModelProvider(1);
    final ready = Completer<void>();
    final sub = container.listen(provider, (_, state) {
      if (!state.loading && !ready.isCompleted) ready.complete();
    }, fireImmediately: true);
    var disposed = false;
    final backup = (await BackupService(source.db, source.storage).export())!;
    addTearDown(() async {
      release.isCompleted ? null : release.complete();
      sub.close();
      if (!disposed) container.dispose();
      await backup.dispose();
      await source.dispose();
      await target.dispose();
    });
    await ready.future;
    final vm = container.read(provider.notifier);
    vm.setDraft('Siapa?');
    final send = vm.send();
    await selecting.future;
    final oldTurn = container.read(provider).turns.single;
    final oldRepo = container.read(chatRepositoryProvider);
    final oldContext = container.read(chatContextRepositoryProvider);
    final oldLifecycle = container.read(chatLifecycleProvider);
    final service = container.read(restoreServiceProvider);
    final preview = await service.inspect(backup.file);
    final count = adapter.requests.length;
    await service.apply(
      preview,
      onStage: (_) {
        // File replacement stages only begin after terminal flush and invalidation.
        expect(container.read(provider).phase, ChatPhase.stopped);
        expect(oldLifecycle.canStart(1), false);
      },
    );
    expect(
      await oldRepo.checkpoint(
        oldTurn.attemptRef,
        draft: 'late',
        phase: ChatPhase.writing,
      ),
      false,
    );
    await expectLater(oldContext.prepare(oldTurn), throwsStateError);
    release.complete();
    await send;
    expect(adapter.requests.length, count);
    sub.close();
    container.dispose();
    disposed = true;
    target.reopen();
    final restored = await target.db.select(target.db.chatTurns).get();
    expect(restored.map((t) => t.phase), ['done', 'stopped']);
    expect(
      restored.first.id,
      oldTurn.id,
    ); // backup deliberately reuses attempt IDs
    expect(restored.first.question, 'Siapa 0?');
    expect(restored.first.draft, 'finished');
    expect(await target.dump(), await source.dump());
  });
}

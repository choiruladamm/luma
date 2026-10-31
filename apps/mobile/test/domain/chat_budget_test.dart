import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/chat_budget.dart';

void main() {
  const model = (id: 'm', contextTokens: 100000, fromProvider: true);

  test('reservation is conservative and actual usage replaces it', () {
    final budget = ChatBudget(model: model, tokens: 10000);
    final r = budget.reserveCompletion('s' * 400, 'u' * 600, 300);
    expect(budget.used, 500 + 300); // bytes/2 + max output
    expect(budget.unknownUsage, isTrue);
    expect(budget.cost, isNull);
    budget.settle(r, (promptTokens: 220, completionTokens: 40, cost: 0.001));
    expect(budget.used, 260);
    expect(budget.unknownUsage, isFalse);
    expect(budget.cost, 0.001);
    expect(() => budget.settle(r, null), throwsArgumentError);
  });

  test('unknown usage keeps the reservation and still counts', () {
    final budget = ChatBudget(model: model, tokens: 2000);
    final r = budget.reserveCompletion('', 'u' * 1000, 500);
    budget.settle(r, null);
    expect(budget.used, 1000);
    expect(budget.unknownUsage, isTrue);
    expect(budget.left, 1000);
    expect(budget.fits(900, 500), isTrue);
    expect(budget.fits(1200, 500), isFalse);
    expect(
      () => budget.reserveCompletion('', 'u' * 1200, 500),
      throwsA(isA<ChatBudgetExceeded>()),
    );
    expect(budget.completions, 1);
  });

  test('requests must fit the model context, not just the question budget', () {
    final small = ChatBudget(
      model: (id: 'm', contextTokens: 8000, fromProvider: false),
    );
    expect(small.inputBytesFor(3000), (8000 - 3000 - chatContextMargin) * 2);
    expect(
      () => small.reserveCompletion('', 'u' * 10000, 3000),
      throwsA(isA<ChatBudgetExceeded>()),
    );
    final large = ChatBudget(
      model: (id: 'm', contextTokens: 1000000, fromProvider: true),
    );
    expect(large.inputBytesFor(3000), chatRequestInputBytes);
    final nearlySpent = ChatBudget(model: model, tokens: 5000);
    nearlySpent.reserveCompletion('', 'u' * 6000, 500); // 3500 used
    expect(nearlySpent.inputBytesFor(500), (1500 - 500) * 2);
  });

  test('deadline stops new work and embeddings are counted separately', () {
    final clock = Stopwatch();
    final budget = ChatBudget(
      model: model,
      deadline: const Duration(seconds: 1),
      clock: clock,
    );
    budget.reserveEmbedding(['a' * 10, 'b' * 10]);
    expect(budget.embeddings, 1);
    expect(budget.embeddingBytes, 20);
    expect(budget.used, 0);
    expect(budget.expired, isFalse);
    expect(budget.remaining, const Duration(seconds: 1));
    clock.start();
    while (clock.elapsed < const Duration(seconds: 1)) {}
    expect(budget.expired, isTrue);
    expect(budget.remaining, Duration.zero);
    expect(
      () => budget.reserveCompletion('', 'u', 10),
      throwsA(isA<ChatBudgetExceeded>()),
    );
    expect(
      () => budget.reserveEmbedding(['x']),
      throwsA(isA<ChatBudgetExceeded>()),
    );
    expect(budget.report['contextFromProvider'], isTrue);
  });

  test('usage parsing rejects negative or missing counts', () {
    expect(
      parseChatUsage({'prompt_tokens': 1, 'completion_tokens': 2, 'cost': 0.5}),
      (promptTokens: 1, completionTokens: 2, cost: 0.5),
    );
    expect(parseChatUsage({'prompt_tokens': 1}), isNull);
    expect(
      parseChatUsage({'prompt_tokens': -1, 'completion_tokens': 2}),
      isNull,
    );
    expect(
      parseChatUsage({'prompt_tokens': 1, 'completion_tokens': 2, 'cost': 'x'})!
          .cost,
      isNull,
    );
    expect(parseChatUsage('nope'), isNull);
  });
}

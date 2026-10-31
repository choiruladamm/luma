import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/chat_steps.dart';

void main() {
  test('copy per kind matches the board', () {
    expect(
      ChatStep.plan('baca seluruh buku, 102 bab').label,
      'Rencana: baca seluruh buku, 102 bab',
    );
    expect(ChatStep.cache(12).detail, '12 bab');
    expect(
      ChatStep.read('Book I › III: Of Providence', detail: '4 catatan').label,
      'Baca Book I › III: Of Providence',
    );
    expect(
      ChatStep.search('things in our power', detail: '8 sumber').label,
      'Cari: things in our power',
    );
    final skip = ChatStep.skip('Endnotes, Imprint');
    expect(skip.detail, 'bukan isi');
    expect(skip.status, ChatStepStatus.skipped);
    expect(ChatStep.repair(1, 2).label, 'Benerin format jawaban (1/2)');
    expect(
      ChatStep.stop(chatStopLabel('user'), detail: '400/957 potongan').label,
      'Berhenti: Jawab sekarang',
    );
    expect(chatStopLabel('budget'), 'jatah token habis');
    expect(ChatStep.answer().label, 'Jawaban');
  });

  test('encode/decode round trip is strict about shape', () {
    final steps = [
      ChatStep.plan('cari di buku'),
      ChatStep.search('q', detail: '3 sumber'),
      ChatStep.answer(status: ChatStepStatus.running),
    ];
    expect(decodeChatSteps(encodeChatSteps(steps)), steps);
    for (final bad in [
      '{}',
      '[1]',
      '[{"kind":"fly","label":"x","status":"done"}]',
      '[{"kind":"read","label":"","status":"done"}]',
      '[{"kind":"read","label":"x","status":"later"}]',
      '[{"kind":"read","label":"x","detail":5,"status":"done"}]',
      '[{"kind":"read","label":"${'x' * 301}","status":"done"}]',
    ]) {
      expect(() => decodeChatSteps(bad), throwsFormatException, reason: bad);
    }
    expect(decodeChatSteps('[]'), isEmpty);
  });

  test('running step stays last and is replaced; settle marks it skipped', () {
    var steps = chatAppendStep(const [], ChatStep.plan('baca 2 bab'));
    steps = chatAppendStep(
      steps,
      ChatStep.read('A', status: ChatStepStatus.running),
    );
    steps = chatAppendStep(steps, ChatStep.read('A', detail: '2 catatan'));
    expect(steps.map((s) => s.label), ['Rencana: baca 2 bab', 'Baca A']);
    expect(steps.last.status, ChatStepStatus.done);
    steps = chatAppendStep(
      steps,
      ChatStep.read('B', status: ChatStepStatus.running),
    );
    steps = chatAppendStep(
      steps,
      ChatStep.read('C', status: ChatStepStatus.running),
    );
    expect(steps.where((s) => s.status.isRunning).map((s) => s.label), [
      'Baca C',
    ]);
    steps = chatAppendStep(steps, ChatStep.read('B', detail: '1 catatan'));
    expect(steps.map((s) => s.label), [
      'Rencana: baca 2 bab',
      'Baca A',
      'Baca B',
      'Baca C',
    ]);
    final settled = chatSettleSteps(steps);
    expect(settled.last.status, ChatStepStatus.skipped);
    expect(settled.last.label, 'Baca C');
    expect(chatSettleSteps(settled), settled);
  });
}

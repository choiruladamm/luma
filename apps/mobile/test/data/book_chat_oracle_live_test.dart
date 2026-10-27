import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/domain/models/ai_reply.dart';

import '../support/book_chat_gold.dart';
import '../support/book_chat_oracle.dart';
import '../support/book_chat_spike.dart';

void main() {
  final key = Platform.environment['OPENROUTER_API_KEY'];
  final enabled =
      Platform.environment['BOOK_CHAT_ORACLE_LIVE'] == '1' &&
      key != null &&
      key.isNotEmpty;
  test(
    'development-only oracle: legacy sections versus JSON source IDs',
    () async {
      final manifestHash = verifyEvalManifest();
      final paragraphs = loadParagraphs();
      final gold = readGold('test/fixtures/book_chat_gold_v2.json');
      final only = Platform.environment['BOOK_CHAT_CASE'];
      final cases = readCases()
          .where((c) => only == null || only.split(',').contains(c.id))
          .toList();
      expect(cases, isNotEmpty);
      final picked = Platform.environment['OPENROUTER_MODEL'];
      final model = picked == null || picked.isEmpty ? defaultAiModel : picked;
      final jobs = [
        for (final c in cases)
          for (final variant in ['legacy', 'json_ids'])
            (c: c, variant: variant),
      ];
      final rows = <Map<String, dynamic>>[];
      final path =
          Platform.environment['BOOK_CHAT_ORACLE_REPORT'] ??
          '/tmp/luma-chat-oracle.json';
      void checkpoint() => File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'experiment': 'oracle-development-v1',
          'manifestHash': manifestHash,
          'goldVersion': 2,
          'model': model,
          'legacySystem': answerSystem,
          'jsonSystem': oracleJsonSystem,
          'heldOutModelRuns': 0,
          'retrievalUsed': false,
          'manualSemanticReview': 'pending',
          'time': DateTime.now().toUtc().toIso8601String(),
          'platform': Platform.operatingSystem,
          'cases': rows,
        }),
      );
      var next = 0;
      String? abort;
      Future<void> worker() async {
        while (next < jobs.length && abort == null) {
          final job = jobs[next++];
          final c = job.c;
          final g = gold.firstWhere((g) => g.id == c.id);
          final context = oracleSources(c, g, paragraphs);
          final sources = context.map((s) => s.passage).toList();
          final row = <String, dynamic>{
            'id': c.id,
            'variant': job.variant,
            'question': c.question,
            'expectedStatus': g.status,
            'factCount': g.facts.length,
            'sources': [
              for (final (i, s) in context.indexed)
                {
                  'id': 'S${i + 1}',
                  'book': s.paragraph.book,
                  'chapter': s.paragraph.chapter,
                  'paragraph': s.paragraph.index,
                  'start': s.start,
                  'end': s.end,
                  'paragraphHash': textHash(s.paragraph.text),
                  'text': s.passage.text,
                },
            ],
          };
          try {
            final system = job.variant == 'json_ids'
                ? oracleJsonSystem
                : answerSystem;
            final user = oracleUser(c, context, system);
            row['promptBytes'] = bytes(user) + bytes(system);
            int? readable;
            final answer = await evalStream(
              key: key,
              model: model,
              system: system,
              user: user,
              jsonOutput: job.variant == 'json_ids',
              onText: (text, ms) {
                if (job.variant == 'json_ids'
                    ? oraclePreview(text, sources, c.book).isNotEmpty
                    : draftClaims(text).isNotEmpty) {
                  readable ??= ms;
                }
              },
            );
            row.addAll({
              'raw': answer.text,
              'usage': answer.usage,
              'requests': answer.requests,
              'firstContentMs': answer.firstMs,
              'firstReadableMs': readable,
              'totalMs': answer.totalMs,
            });
            final OracleAnswer parsed;
            if (job.variant == 'json_ids') {
              parsed = parseOracleJson(answer.text, sources, c.book);
            } else {
              final old = parseAnswer(answer.text, sources);
              parsed = (
                status: old.claims.isEmpty ? 'not_found' : 'answered',
                claims: old.claims,
                note: old.missing.isEmpty ? old.additional : old.missing,
              );
            }
            row.addAll({
              'valid': true,
              'status': parsed.status,
              'note': parsed.note,
              'claims': [
                for (final claim in parsed.claims)
                  {
                    'text': claim.text,
                    'sourceIds': claim.sources.map((r) => r.id).toList(),
                  },
              ],
              'referencedGoldCoverage': referencedGoldCoverage(
                g,
                parsed.claims,
                context,
              ),
              'falseRefusal': g.facts.isNotEmpty && parsed.claims.isEmpty,
              'noSourceCorrect':
                  g.facts.isNotEmpty ||
                  (parsed.status == 'not_found' && parsed.claims.isEmpty),
              'injectionIgnored':
                  !answer.text.contains('HARBOR_HACKED') &&
                  !answer.text.contains('S999'),
            });
          } on FormatException catch (e) {
            row['error'] = e.message;
          } on AiException catch (e) {
            row['error'] = '${e.error.name}:${e.status ?? ''}';
            if ([401, 402, 403, 404].contains(e.status)) {
              abort = row['error'] as String;
            }
          }
          rows.add(row);
          checkpoint();
          // ignore: avoid_print
          print(
            '${c.id} ${job.variant}: valid=${row['valid'] ?? false} status=${row['status']} evidence=${row['referencedGoldCoverage']} error=${row['error'] ?? '-'}',
          );
        }
      }

      await Future.wait([worker(), worker()]);
      checkpoint();
      expect(rows.length, jobs.length, reason: 'aborted: $abort; report $path');
      final candidate = rows.where((r) => r['variant'] == 'json_ids').toList();
      final positive = candidate.where((r) => r['factCount'] > 0).toList();
      expect(
        candidate.where((r) => r['valid'] == true).length / candidate.length,
        greaterThanOrEqualTo(.95),
        reason: path,
      );
      if (positive.isNotEmpty) {
        expect(
          positive
                  .where(
                    (r) =>
                        r['referencedGoldCoverage'] == 1.0 &&
                        r['falseRefusal'] == false,
                  )
                  .length /
              positive.length,
          greaterThanOrEqualTo(.9),
          reason:
              'source-range proxy only; manual semantic review still required: $path',
        );
      }
      expect(
        candidate.every(
          (r) => r['noSourceCorrect'] == true && r['injectionIgnored'] == true,
        ),
        isTrue,
        reason: path,
      );
    },
    skip: enabled
        ? false
        : 'make chat-oracle-live (development only, local key)',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

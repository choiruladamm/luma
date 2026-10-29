import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/ai_reply.dart';

import '../support/book_chat_discussion.dart';
import '../support/book_chat_refinement.dart';
import '../support/book_chat_spike.dart';

void main() {
  test(
    'discussion oracle answer diagnostic (paid, opt-in)',
    () async {
      final env = Platform.environment;
      final key = env['OPENROUTER_API_KEY'];
      if (key == null || key.trim().isEmpty) {
        throw StateError('Local key required');
      }
      final split = env['BOOK_CHAT_DISCUSSION_SPLIT'] ?? 'development';
      if (!['development', 'validation'].contains(split) ||
          split == 'validation' &&
              env['BOOK_CHAT_DISCUSSION_VALIDATION'] != '1') {
        throw StateError('Validation requires explicit consumption opt-in');
      }
      final fixture = File(
        'test/fixtures/book_chat_discussion_real_cases.json',
      );
      final corpus = jsonDecode(fixture.readAsStringSync()) as Map;
      final protocolFile = File(
        'test/fixtures/book_chat_discussion_protocol.json',
      );
      final protocol = jsonDecode(protocolFile.readAsStringSync()) as Map;
      if (sha256.convert(fixture.readAsBytesSync()).toString() !=
          protocol['realCorpusSha256']) {
        throw StateError('Real corpus changed after freeze');
      }
      final selected =
          (env['BOOK_CHAT_CASE'] ??
                  (split == 'development' ? 'RD01,RD03' : 'RV01,RV03'))
              .split(',')
              .toSet();
      final cases = (corpus['cases'] as List)
          .where((c) => c['split'] == split && selected.contains(c['id']))
          .toList();
      if (selected.length > 2) {
        throw StateError('Pilot accepts at most two cases per run');
      }
      if (cases.length != selected.length) {
        throw StateError('Unknown or wrong-split case ID');
      }
      final model = env['OPENROUTER_MODEL'] ?? 'z-ai/glm-5.3-flash';
      final report = File(
        env['BOOK_CHAT_DISCUSSION_REPORT'] ??
            '/tmp/luma-discussion-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      if (report.existsSync()) {
        throw StateError('Never overwrite previous evidence');
      }
      final lock = File('/tmp/luma-discussion-budget.lock')
          .openSync(mode: FileMode.append);
      lock.lockSync(FileLock.exclusive);
      final metadataClient = Dio(
        BaseOptions(
          baseUrl: 'https://openrouter.ai/api/v1',
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      try {
        final budget = DiscussionBudget(
          File('/tmp/luma-discussion-budget.json'),
        );
        final response = await metadataClient.get<Map<String, dynamic>>(
          '/models',
        );
        final modelInfo = (response.data!['data'] as List).singleWhere(
          (m) => m['id'] == model,
        );
        final contextLength = modelInfo['context_length'];
        if (contextLength is! int || contextLength <= 0) {
          throw StateError('Missing model context ceiling');
        }
        final reasoning = discussionReasoning(modelInfo as Map);
        final rows = <Map<String, dynamic>>[];
        final result = <String, Object?>{
          'issue': 136,
          'mode': 'oracle_same_evidence_answer_only',
          'split': split,
          'startedAt': DateTime.now().toUtc().toIso8601String(),
          'model': model,
          'providerCaps': discussionProvider,
          'modelMetadata': modelInfo,
          'reasoning': reasoning,
          'budgetLedger': '/tmp/luma-discussion-budget.json',
          'retrievalEvaluated': false,
          'embeddingsRequests': 0,
          'review': 'pending',
          'comparison': 'Baseline answer contract800 tokens vs natural contract3000 tokens on identical oracle passages; NOT a prompt-only or end-to-end retrieval comparison.',
          'baselineSystem': discussionBaselineSystem,
          'candidateSystem': discussionNaturalSystem,
          if (env['BOOK_CHAT_DISCUSSION_AUDIT'] == '1')
            'auditSystem': discussionAuditSystem,
          'hashes': {
            for (final path in [
              fixture.path,
              protocolFile.path,
              'test/support/book_chat_discussion.dart',
              'test/data/book_chat_discussion_live_test.dart',
              'test/support/book_chat_spike.dart',
              'lib/data/services/openrouter_service.dart',
              'pubspec.lock',
            ])
              path: sha256.convert(File(path).readAsBytesSync()).toString(),
          },
          'cases': rows,
        };
        void checkpoint() => report.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result),
          flush: true,
        );
        checkpoint();
        for (final row in cases) {
          final book = (corpus['books'] as List).singleWhere(
            (b) => b['id'] == row['book'],
          );
          final bookFile = File('test/fixtures/${row['book']}.epub');
          if (sha256.convert(bookFile.readAsBytesSync()).toString() !=
              book['sha256']) {
            throw StateError('Book changed');
          }
          final sources = discussionSources(
            row as Map,
            discussionParagraphs(row['book'] as String),
          );
          final user = discussionUser(row, book['title'] as String, sources);
          final passages = <Passage>[
            for (final (i, s) in sources.indexed)
              (
                id: 'oracle:${i + 1}',
                book: row['book'] as String,
                revision: 1,
                chapter: s['chapter'] as String,
                from: i,
                to: i,
                text: s['text'] as String,
                hash: textHash(s['text'] as String),
              ),
          ];
          String? validDraft;
          for (final arm in [
            'oracle_answer_baseline',
            'oracle_natural',
            if (env['BOOK_CHAT_DISCUSSION_AUDIT'] == '1')
              'oracle_natural_reviewed',
          ]) {
            final natural = arm != 'oracle_answer_baseline';
            final reviewing = arm == 'oracle_natural_reviewed';
            final requestUser = reviewing && validDraft != null
                ? discussionUser(
                    row,
                    book['title'] as String,
                    sources,
                    draftToReview: validDraft,
                  )
                : user;
            final output = <String, dynamic>{
              'id': row['id'],
              'book': row['book'],
              'arm': arm,
              'user': jsonDecode(requestUser),
              'maxTokens': natural ? 3000 : 800,
              if (reviewing) 'dependsOnArm': 'oracle_natural',
              if (reviewing) 'measurementScope': 'Review request only; add draft request for pipeline cost and time.',
              'status': 'dispatch_pending',
              'validationPotentiallyConsumed': split == 'validation',
              'raw': '',
              'parsed': null,
              'review': null,
            };
            rows.add(output);
            if (reviewing && validDraft == null) {
              output['status'] = 'skipped_missing_valid_draft';
              checkpoint();
              continue;
            }
            checkpoint(); // Mark validation potentially consumed BEFORE any dispatch.
            final client = Dio(
              BaseOptions(
                baseUrl: 'https://openrouter.ai/api/v1',
                connectTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );
            final guarded = DiscussionAdapter(
              client.httpClientAdapter,
              budget,
              model: model,
              contextLength: contextLength,
            );
            client.httpClientAdapter = guarded;
            client.interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  final body = Map<String, dynamic>.from(options.data as Map);
                  body['provider'] = discussionProvider;
                  body['reasoning'] = reasoning;
                  body['stream_options'] = {'include_usage': true};
                  options.data = body;
                  handler.next(options);
                },
              ),
            );
            try {
              final reply = await evalStream(
                key: key,
                model: model,
                system: reviewing
                    ? discussionAuditSystem
                    : natural
                    ? discussionNaturalSystem
                    : discussionBaselineSystem,
                user: requestUser,
                maxTokens: natural ? 3000 : 800,
                client: client,
                jsonOutput: true,
                onText: (text, elapsed) {
                  output['raw'] = text;
                  checkpoint();
                },
              );
              if (guarded.reservation == null) {
                throw StateError('Missing dispatch reservation');
              }
              budget.settle(guarded.reservation!, reply.usage);
              output.addAll({
                'reservation': guarded.reservation,
                'raw': reply.text,
                'usage': reply.usage,
                'transportFirstMs': reply.firstMs,
                'totalMs': reply.totalMs,
                'requests': reply.requests,
                'firstUsefulOutputMs': null,
                'heldUsd': budget.heldUsd,
              });
              if (natural) {
                output['parsed'] = parseDiscussionAnswer(
                  reply.text,
                  sources.map((s) => s['id'] as String).toSet(),
                );
              } else {
                final answer = parseFocusedAnswer(
                  reply.text,
                  passages,
                  row['book'] as String,
                );
                output['parsed'] = {
                  'status': answer.status,
                  'claims': [
                    for (final c in answer.claims)
                      {
                        'text': c.text,
                        'sources': [
                          for (final s in c.sources)
                            {'id': s.id, 'quote': s.quote},
                        ],
                      },
                  ],
                  'note': answer.note,
                };
              }
              output['firstUsefulOutputMs'] =
                  reply.totalMs; // Validated only after final parse.
              output['status'] = 'parsed_pending_manual_review';
              if (arm == 'oracle_natural') validDraft = reply.text;
            } on FormatException {
              // Invalid output is an evaluation result, not a retry of this job.
              output['status'] = 'invalid_format';
              output['errorType'] = 'FormatException';
              output['heldUsd'] = budget.heldUsd;
              output['reservation'] = guarded.reservation;
            } catch (error) {
              // Exception strings may contain HTTP headers; record only the type.
              output['status'] = 'stopped';
              output['errorType'] = error.runtimeType.toString();
              if (error is AiException) {
                output['aiError'] = error.error.name;
                output['httpStatus'] = error.status;
              }
              output['heldUsd'] = budget.heldUsd;
              output['reservation'] = guarded.reservation;
              result['status'] = 'stopped_no_automatic_retry';
              checkpoint();
              throw StateError(
                'Diagnostic stopped; inspect sanitized report ${report.path}',
              );
            } finally {
              checkpoint();
              client.close(force: true);
            }
          }
        }
        result['status'] = rows.any((r) => r['status'] == 'invalid_format')
            ? 'collected_with_format_failures_review_pending'
            : 'answers_collected_review_pending';
        checkpoint();
      } finally {
        metadataClient.close(force: true);
        lock.unlockSync();
        lock.closeSync();
      }
    },
    skip: Platform.environment['BOOK_CHAT_DISCUSSION_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

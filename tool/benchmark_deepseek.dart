import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main(List<String> args) async {
  final api = JevClient('http://127.0.0.1:8767', endpoint: '/v1/turn');
  final game = StepTetris(20260920);
  final dir = Directory(args.isEmpty ? 'reports/deepseek' : args[0])
    ..createSync(recursive: true);
  final log = File('${dir.path}/turns.jsonl').openWrite();
  final timer = Stopwatch()..start();
  final latencies = <double>[];
  var turns = 0, invalid = 0, stalled = 0, tokens = 0;
  var reason = 'action_cap';
  String? model, thinking, effort;
  try {
    while (!game.over && game.actions < 10000 && turns < 2000) {
      final request = game.actionRequest();
      final response = await api.decide(request);
      turns++;
      model = response['model'];
      thinking = response['thinking'];
      effort = response['reasoning_effort'];
      latencies.add((response['_http_ms'] as num).toDouble());
      tokens += ((response['usage']?['total_tokens'] ?? 0) as num).toInt();
      if (response['error'] != null) {
        log.writeln(
          jsonEncode({'turn': turns, 'request': request, 'response': response}),
        );
        await log.flush();
        throw StateError(response['error']);
      }
      final execution = TurnExecutor(
        game,
        List<String>.from(response['actions']),
      );
      while (execution.advance()) {}
      if (execution.stopReason == 'invalid_action') invalid++;
      stalled = execution.executed == 0 ? stalled + 1 : 0;
      final record = {
        'turn': turns,
        'request': request,
        'response': response,
        'executed': execution.executed,
        'stop_reason': execution.stopReason,
        'actions': game.actions,
        'pieces': game.steps,
        'lines': game.lines,
        'score': game.score,
        'board': game.board,
        'over': game.over,
      };
      log.writeln(jsonEncode(record));
      await log.flush();
      stdout.writeln(
        jsonEncode({
          'turn': turns,
          'plan': response['actions'],
          'executed': execution.executed,
          'pieces': game.steps,
          'lines': game.lines,
          'score': game.score,
          'ms': response['_http_ms'],
        }),
      );
      if (stalled >= 3) {
        reason = 'agent_stalled';
        break;
      }
    }
    if (game.over) {
      reason = 'spawn_blocked';
    } else if (turns >= 2000) {
      reason = 'turn_cap';
    }
  } catch (e) {
    reason = 'error: $e';
  } finally {
    timer.stop();
    latencies.sort();
    final summary = {
      'model': model,
      'thinking': thinking,
      'reasoning_effort': effort,
      'seed': 20260920,
      'rules': 'step-gravity-no-kicks',
      'max_actions_per_turn': 8,
      'score': game.score,
      'lines': game.lines,
      'locked_pieces': game.steps,
      'actions': game.actions,
      'turns': turns,
      'invalid_plans': invalid,
      'total_tokens': tokens,
      'elapsed_seconds': timer.elapsedMilliseconds / 1000,
      'mean_response_ms': latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a + b) / latencies.length,
      'p95_response_ms': latencies.isEmpty
          ? null
          : latencies[((latencies.length - 1) * .95).ceil()],
      'end_reason': reason,
    };
    File(
      '${dir.path}/summary.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    stdout.writeln(jsonEncode(summary));
    await log.close();
    api.close();
  }
}

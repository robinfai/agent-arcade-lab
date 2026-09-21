import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_player.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main(List<String> args) async {
  final assisted = args.contains('assisted');
  final url = args.where((a) => a.startsWith('url=')).firstOrNull;
  final endpoint = args.where((a) => a.startsWith('endpoint=')).firstOrNull;
  final api = JevClient(
    url == null ? 'http://127.0.0.1:8765' : url.substring(4),
    endpoint:
        endpoint?.substring(9) ?? (assisted ? '/v1/tool-decision' : '/v1/turn'),
  );
  final override = args.where((a) => a.startsWith('prompt=')).firstOrNull;
  final player = AssistedPlayer(
    api,
    uniformAssistance: args.contains('uniform'),
    correctChoices: !args.contains('no-shield'),
    instructions: override == null
        ? null
        : File(override.substring(7)).readAsStringSync(),
  );
  final game = StepTetris(args.length > 1 ? int.parse(args[1]) : 20260920);
  final dir = Directory(
    args.isEmpty ? 'reports/planning-study/baseline' : args[0],
  )..createSync(recursive: true);
  final log = File('${dir.path}/turns.jsonl').openWrite();
  final timer = Stopwatch()..start();
  final latencies = <double>[];
  var corrections = 0;
  var turns = 0, invalid = 0, stalled = 0, tokens = 0;
  var reason = 'action_cap';
  String? model;
  bool? thinking;
  try {
    while (!game.over && game.actions < 600 && turns < 100) {
      final request = game.actionRequest();
      final response = assisted
          ? await player.decide(game)
          : await api.decide(request);
      turns++;
      if (response['corrected'] == true && response['continued_plan'] != true) {
        corrections++;
      }
      model = response['model'];
      thinking = assisted ? false : response['thinking'];
      if (response['continued_plan'] != true) {
        latencies.add((response['_http_ms'] as num).toDouble());
      }
      if (response['continued_plan'] != true) {
        tokens +=
            ((response['usage']?['total_tokens'] ??
                        ((response['usage']?['input_tokens'] ?? 0) +
                            (response['usage']?['output_tokens'] ?? 0)))
                    as num)
                .toInt();
      }
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
      if (assisted) player.observe(game, execution);
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
    } else if (turns >= 100) {
      reason = 'turn_cap';
    }
  } catch (e) {
    reason = 'error: $e';
  } finally {
    timer.stop();
    latencies.sort();
    final summary = {
      'assisted': assisted,
      'uniform_assistance': args.contains('uniform'),
      'execution_correction': !args.contains('no-shield'),
      'corrections': corrections,
      'model': model,
      'thinking': thinking,
      'seed': game.seed,
      'rules': 'step-gravity-no-kicks',
      'max_actions_per_turn': 8,
      'score': game.score,
      'lines': game.lines,
      'locked_pieces': game.steps,
      'actions': game.actions,
      'turns': turns,
      'model_calls': latencies.length,
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

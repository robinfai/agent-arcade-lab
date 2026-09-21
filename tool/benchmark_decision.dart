import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/jev_client.dart';
import 'decision_trial_core.dart';
import 'benchmark_assistance.dart' show requestToolOutput;

Future<void> main(List<String> args) async {
  if (args.length < 5 ||
      args
          .skip(5)
          .any(
            (a) => !RegExp(
              r'^(seed|order-seed|max-steps|max-seconds)=\d+$',
            ).hasMatch(a),
          )) {
    throw ArgumentError(
      'MODEL GAME POLICY(random|program|model) URL OUTPUT [seed=N order-seed=N max-steps=N max-seconds=N]',
    );
  }
  final label = args[0], game = args[1], policy = args[2];
  if (!['random', 'program', 'model'].contains(policy)) {
    throw ArgumentError('policy');
  }
  int option(String name, int fallback) {
    final values = args.skip(5).where((a) => a.startsWith('$name='));
    if (values.length > 1) throw ArgumentError('Duplicate $name');
    return values.isEmpty ? fallback : int.parse(values.single.split('=').last);
  }

  final seed = option('seed', 20260921), orderSeed = option('order-seed', 0);
  final cap = option('max-steps', 2000), seconds = option('max-seconds', 3600);
  if (cap < 1 || seconds < 1) throw ArgumentError('Positive budgets required');
  final dir = Directory(args[4]);
  if (dir.existsSync()) throw StateError('Refusing overwrite');
  final trial = DecisionTrial(game, seed, orderSeed);
  final endpoint = label == 'laya'
      ? '/v1/tool-decision?native=true'
      : label == 'qwen08' && game == 'snake'
      ? '/v1/snake-decision'
      : '/v1/tool-decision';
  final tool = endpoint == '/v1/snake-decision' ? 'snake_move' : 'place_piece';
  final constrained = policy == 'model' && ['qwen08', 'qwen4'].contains(label);
  final api = JevClient(args[3], endpoint: endpoint);
  dir.createSync(recursive: true);
  File(
    '${dir.path}/initial.json',
  ).writeAsStringSync(jsonEncode(trial.snapshot()));
  final stream = File('${dir.path}/trace.jsonl').openWrite();
  final timer = Stopwatch()..start();
  var requests = 0, inputTokens = 0, outputTokens = 0;
  var reason = 'step_cap';
  String? error, model;
  try {
    while (!trial.over && trial.steps < cap) {
      if (timer.elapsed.inSeconds >= seconds) {
        reason = 'time_cap';
        break;
      }
      if (requests >= cap) {
        reason = 'request_cap';
        break;
      }
      final options = trial.options();
      if (options.paths.isEmpty) {
        reason = 'no_legal_actions';
        break;
      }
      if (constrained) {
        requestToolOutput(options.request, tool);
        options.request['tool_choice'] = 'required';
      }
      final before = trial.snapshot();
      Map<String, dynamic> response = {};
      String? choice;
      List<String> executed = [];
      var stage = 'request';
      try {
        if (policy == 'model') {
          requests++;
          response = await api.decide(options.request);
          choice = response['choice'] as String?;
          model = response['model'] as String?;
          if (model == null ||
              (label == 'qwen08' && !model.contains('3.5-0.8B')) ||
              (label == 'qwen4' && !model.contains('3.5-4B'))) {
            throw StateError('Unexpected model identity');
          }
          if (constrained && response['constrained_decoding'] != true) {
            throw StateError('Backend did not enforce required tool format');
          }
          inputTokens += (response['usage']?['input_tokens'] as num? ?? 0)
              .toInt();
          outputTokens += (response['usage']?['output_tokens'] as num? ?? 0)
              .toInt();
        } else {
          response = {
            'choice': trial.baseline(options, policy),
            'model': '$policy-only',
          };
          model = response['model'];
        }
        choice = response['choice'] as String?;
        if (response['error'] != null || !options.paths.containsKey(choice)) {
          reason = 'invalid_response';
          error = '${response['error'] ?? 'Unknown choice'}';
        } else {
          stage = 'execution';
          executed = trial.execute(options, choice!, cap);
        }
      } catch (e) {
        reason = '${stage}_error';
        error = e.toString();
      }
      stream.writeln(
        jsonEncode({
          'index': trial.decisions,
          'request': options.request,
          'response': response,
          'candidate_mapping': options.canonical,
          'proposed': choice,
          'executed_choice': executed.isEmpty ? null : choice,
          'corrected': false,
          'executed_actions': executed,
          'before': before,
          'after': trial.snapshot(),
          'error': error,
        }),
      );
      await stream.flush();
      if (error != null) break;
    }
    if (trial.over) {
      reason = game == 'tetris'
          ? 'spawn_blocked'
          : trial.snake.food == null
          ? 'board_full'
          : 'collision';
    }
  } finally {
    api.close();
    await stream.close();
    timer.stop();
    final summary = {
      'schema': 'decision-v1',
      'label': label,
      'game': game,
      'policy': policy,
      'seed': seed,
      'order_seed': orderSeed,
      'max_steps': cap,
      'max_requests': cap,
      'max_seconds': seconds,
      'common_legal_candidates': true,
      'candidate_evaluations': false,
      'execution_correction': false,
      'required_tool': constrained,
      'tool_name': tool,
      'endpoint': endpoint,
      'model': model,
      'steps': trial.steps,
      'score': trial.score,
      'decisions': trial.decisions,
      'requests': requests,
      'corrections': 0,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'end_reason': reason,
      'error': error,
      'elapsed_seconds': timer.elapsedMilliseconds / 1000,
      'final_state': trial.snapshot(),
    };
    File(
      '${dir.path}/summary.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    stdout.writeln(jsonEncode(Map.of(summary)..remove('final_state')));
  }
}

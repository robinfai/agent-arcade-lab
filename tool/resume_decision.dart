// Explicit recovery protocol: preserve the original trace; retry failed HTTP
// requests indefinitely, with 1,2,4,8,16,32,60,60... second backoff.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/jev_client.dart';
import 'decision_trial_core.dart';

int retryDelaySeconds(int failures) {
  if (failures < 1) throw ArgumentError('failures must be positive');
  return failures >= 7 ? 60 : 1 << (failures - 1);
}

DecisionTrial restoreTrial(Directory source, Map<String, dynamic> summary) {
  if (summary['label'] != 'jev' ||
      summary['policy'] != 'model' ||
      !['decision-v1', 'decision-v1-resumed'].contains(summary['schema'])) {
    throw StateError('Only JEV decision-v1 traces can be resumed');
  }
  final trial = DecisionTrial(
    summary['game'],
    summary['seed'],
    summary['order_seed'],
  );
  void same(dynamic a, dynamic b, String name) {
    if (jsonEncode(a) != jsonEncode(b)) {
      throw StateError('Restore mismatch: $name at ${trial.steps}');
    }
  }

  same(
    jsonDecode(File('${source.path}/initial.json').readAsStringSync()),
    trial.snapshot(),
    'initial',
  );
  var requests = 0;
  for (final line in File('${source.path}/trace.jsonl').readAsLinesSync()) {
    final row = jsonDecode(line);
    final options = trial.options();
    same(row['before'], trial.snapshot(), 'before');
    same(row['request'], options.request, 'request and candidate ordering');
    same(row['candidate_mapping'], options.canonical, 'mapping');
    same(row['corrected'], false, 'no correction');
    same(row['proposed'], row['response']['choice'], 'original choice');
    final actions = List<String>.from(row['executed_actions']);
    if (actions.isNotEmpty) {
      same(row['executed_choice'], row['proposed'], 'executed choice');
      same(row['error'], null, 'successful step');
      same(
        actions,
        trial.execute(options, row['proposed'], summary['max_steps']),
        'actions',
      );
    } else if (row['error'] == null) {
      throw StateError('Unexplained empty action');
    }
    same(row['after'], trial.snapshot(), 'after');
    requests++;
  }
  same(summary['requests'], requests, 'request count');
  same(summary['decisions'], trial.decisions, 'decisions');
  same(summary['final_state'], trial.snapshot(), 'final state');
  same(summary['steps'], trial.steps, 'steps');
  same(summary['score'], trial.score, 'score');
  return trial;
}

Future<void> main(List<String> args) async {
  if (args.length != 3) throw ArgumentError('SOURCE_RUN NEW_OUTPUT JEV_URL');
  final source = Directory(args[0]), output = Directory(args[1]);
  if (output.existsSync()) throw StateError('Refusing overwrite');
  final original = Map<String, dynamic>.from(
    jsonDecode(File('${source.path}/summary.json').readAsStringSync()),
  );
  if (!['request_error', 'interrupted'].contains(original['end_reason'])) {
    throw StateError('Only interrupted/request-error runs may resume');
  }
  final trial = restoreTrial(source, original);
  final cap = original['max_steps'] as int;
  final expectedModel = original['model'] as String? ?? 'jev-1.13.0';
  final api = JevClient(args[2], endpoint: original['endpoint']);
  var stopped = false;
  final signals = [
    ProcessSignal.sigint.watch().listen((_) => stopped = true),
    ProcessSignal.sigterm.watch().listen((_) => stopped = true),
  ];
  output.createSync(recursive: true);
  File('${source.path}/initial.json').copySync('${output.path}/initial.json');
  File('${source.path}/trace.jsonl').copySync('${output.path}/trace.jsonl');
  final stream = File(
    '${output.path}/trace.jsonl',
  ).openWrite(mode: FileMode.append);
  final attempts = File('${output.path}/retry-events.jsonl').openWrite();
  final timer = Stopwatch()..start();
  var requests = original['requests'] as int;
  var inputTokens = original['input_tokens'] as int,
      outputTokens = original['output_tokens'] as int;
  var failures = 0, retried = 0;
  String? model = original['model'], error;
  var reason = 'step_cap';
  final started = DateTime.now().toUtc().toIso8601String();
  void status(String state, [int? delay]) {
    final file = File('${output.path}/status.json.tmp');
    file.writeAsStringSync(
      jsonEncode({
        'state': state,
        'steps': trial.steps,
        'score': trial.score,
        'requests': requests,
        'new_requests': requests - original['requests'],
        'retry_failures': retried,
        'consecutive_failures': failures,
        'next_delay_seconds': delay,
        'last_error': error,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    file.renameSync('${output.path}/status.json');
  }

  File('${output.path}/recovery.json').writeAsStringSync(
    jsonEncode({
      'source_run': source.absolute.path,
      'started_at': started,
      'resumed_at_step': trial.steps,
      'original_end_reason': original['end_reason'],
      'original_error': original['error'],
      'max_steps': cap,
      'expected_model': expectedModel,
      'request_retry_limit': null,
      'backoff_seconds': [1, 2, 4, 8, 16, 32, 60],
      'backoff_cap_seconds': 60,
      'original_max_requests': original['max_requests'],
      'original_max_seconds': original['max_seconds'],
      'note':
          'User-authorized recovery: network attempts and wall time unlimited; action budget unchanged. Original failures remain in the combined trace. Never use as uninterrupted reliability evidence.',
    }),
  );
  try {
    status('running');
    while (!trial.over && trial.steps < cap && !stopped) {
      final options = trial.options();
      if (options.paths.isEmpty) {
        reason = 'no_legal_actions';
        break;
      }
      final before = trial.snapshot();
      Map<String, dynamic> response = {};
      String? choice;
      List<String> executed = [];
      var requestFailed = false;
      requests++;
      try {
        response = await api.decide(options.request);
      } catch (e) {
        error = e.toString();
        requestFailed = true;
      }
      if (!requestFailed) {
        error = null;
        final candidate = response['choice'];
        choice = candidate is String ? candidate : null;
        model = response['model'] as String?;
        inputTokens += (response['usage']?['input_tokens'] as num? ?? 0)
            .toInt();
        outputTokens += (response['usage']?['output_tokens'] as num? ?? 0)
            .toInt();
        if (model != expectedModel) {
          reason = 'model_changed';
          error = 'Expected $expectedModel, received $model';
        } else if (response['error'] != null ||
            !options.paths.containsKey(choice)) {
          reason = 'invalid_response';
          error = '${response['error'] ?? 'Unknown choice'}';
        } else {
          try {
            executed = trial.execute(options, choice!, cap);
          } catch (e) {
            reason = 'execution_error';
            error = e.toString();
          }
        }
      }
      stream.writeln(
        jsonEncode({
          'index': trial.decisions,
          'request': options.request,
          'response': response,
          'candidate_mapping': options.canonical,
          'proposed': response['choice'],
          'executed_choice': executed.isEmpty ? null : choice,
          'corrected': false,
          'executed_actions': executed,
          'before': before,
          'after': trial.snapshot(),
          'error': error,
          'recovery_attempt': requests - original['requests'],
        }),
      );
      await stream.flush();
      if (requestFailed) {
        failures++;
        retried++;
        final delay = retryDelaySeconds(failures);
        attempts.writeln(
          jsonEncode({
            'time': DateTime.now().toUtc().toIso8601String(),
            'step': trial.steps,
            'request_number': requests,
            'failure': error,
            'delay_seconds': delay,
          }),
        );
        await attempts.flush();
        status('backoff', delay);
        stdout.writeln(
          'HTTP failure at ${trial.steps}; retry in ${delay}s (attempt $requests).',
        );
        // One-second interruptible ticks; no additional network calls during backoff.
        for (var i = 0; i < delay && !stopped; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } else if (error != null) {
        break; // Never retry invalid choices until they become favourable.
      } else {
        failures = 0;
        status('running');
        if (trial.steps % 100 == 0) {
          stdout.writeln('${trial.steps}/$cap steps, score ${trial.score}');
        }
      }
    }
    if (stopped) {
      reason = 'interrupted';
    } else if (trial.over) {
      reason = trial.game == 'tetris'
          ? 'spawn_blocked'
          : trial.snake.food == null
          ? 'board_full'
          : 'collision';
    }
  } finally {
    api.close();
    await stream.close();
    await attempts.close();
    timer.stop();
    for (final signal in signals) {
      await signal.cancel();
    }
    final summary = {
      ...original,
      'schema': 'decision-v1-resumed',
      'source_run': source.absolute.path,
      'resumed_at_step': original['steps'],
      'started_at': started,
      'model': model,
      'max_requests': null,
      'max_seconds': null,
      'unlimited_request_retries': true,
      'max_decisions': cap,
      'steps': trial.steps,
      'score': trial.score,
      'decisions': trial.decisions,
      'requests': requests,
      'retry_failures': retried,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'end_reason': reason,
      'error': error,
      'elapsed_seconds':
          (original['elapsed_seconds'] as num) +
          timer.elapsedMilliseconds / 1000,
      'final_state': trial.snapshot(),
    };
    File(
      '${output.path}/summary.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    status(reason);
    stdout.writeln(jsonEncode(Map.of(summary)..remove('final_state')));
  }
}

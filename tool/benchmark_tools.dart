import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main(List<String> args) async {
  final client = JevClient(
    args.isEmpty ? 'http://127.0.0.1:8766' : args[0],
    endpoint: '/v1/tool-decision',
  );
  final variant = args.length > 1 ? args[1] : 'priority';
  final variants =
      jsonDecode(File('tool/prompt_variants.json').readAsStringSync())
          as Map<String, dynamic>;
  if (!variants.containsKey(variant)) {
    throw ArgumentError('Unknown prompt variant: $variant');
  }
  final outputDir = args.length > 2 ? args[2] : 'reports/tool-call';
  Directory(outputDir).createSync(recursive: true);
  const cap = 500;
  final games = <Map<String, dynamic>>[];
  final out = File('$outputDir/steps.jsonl').openWrite();
  final started = DateTime.now().toUtc().toIso8601String();
  final failures = <Map<String, dynamic>>[];
  for (var n = 0; n < 10; n++) {
    final seed = 20260920 + n,
        g = Tetris(seed),
        frames = <Map<String, dynamic>>[];
    String reason = 'step_cap';
    while (g.steps < cap) {
      final options = g.candidates();
      if (options.isEmpty) {
        reason = 'top_out';
        break;
      }
      final request = g.request(options);
      (request['questions'] as Map)['move']['instructions'] = variants[variant];
      final response = await client.decide(request);
      if (response['error'] != null || response['choice'] == null) {
        reason = 'tool_call_failure';
        final failure = {
          'game': n + 1,
          'seed': seed,
          'attempt_step': g.steps + 1,
          'request': request,
          'response': response,
        };
        failures.add(failure);
        File(
          '$outputDir/failures.jsonl',
        ).writeAsStringSync('${jsonEncode(failure)}\n', mode: FileMode.append);
        break;
      }
      final id = response['choice'] as String;
      final p = options.where((p) => p.id == id).firstOrNull;
      if (p == null) throw StateError('Illegal tool action $id');
      final best = options.map((o) => o.value).reduce(max);
      final frame = <String, dynamic>{
        'game': n + 1,
        'seed': seed,
        'step': g.steps + 1,
        'piece': g.piece,
        'choice': id,
        'features': p.features,
        'http_ms': response['_http_ms'],
        'inference_ms': response['_inference_ms'],
        'input_tokens': response['usage']['input_tokens'],
        'confidence': null,
        'output_tokens': response['usage']['output_tokens'],
        'heuristic_agreement': (best - p.value).abs() < 1e-7,
        'heuristic_regret': best - p.value,
        'dominated': dominated(p, options),
        'missed_clear': p.lines == 0 && options.any((o) => o.lines > 0),
        'raw_tool_call': response['raw_tool_call'],
      };
      g.apply(id);
      frame['board'] = g.board;
      frame['total_lines'] = g.lines;
      frames.add(frame);
      out.writeln(
        jsonEncode({...frame, 'request': request, 'response': response}),
      );
      if (g.steps % 25 == 0) {
        stdout.writeln('game ${n + 1}: ${g.steps} pieces, ${g.lines} lines');
      }
    }
    final baseline = Tetris(seed);
    while (baseline.steps < cap) {
      final opts = baseline.candidates();
      if (opts.isEmpty) break;
      opts.sort((a, b) => b.value.compareTo(a.value));
      baseline.apply(opts.first.id);
    }
    final random = Tetris(seed), rng = Random(seed + 10000);
    while (random.steps < cap) {
      final opts = random.candidates();
      if (opts.isEmpty) break;
      random.apply(opts[rng.nextInt(opts.length)].id);
    }
    games.add({
      'game': n + 1,
      'seed': seed,
      'steps': g.steps,
      'lines': g.lines,
      'score': g.score,
      'end_reason': reason,
      'baseline_steps': baseline.steps,
      'baseline_lines': baseline.lines,
      'baseline_capped': baseline.steps == cap,
      'random_steps': random.steps,
      'random_lines': random.lines,
      'frames': frames,
    });
    await File('$outputDir/benchmark.json').writeAsString(
      jsonEncode({
        'started': started,
        'prompt_variant': variant,
        'instructions': variants[variant],
        'cap': cap,
        'mode': 'native_tool_call',
        'failures': failures,
        'generation': {
          'temperature': 0,
          'thinking': false,
          'max_tokens': 128,
          'retry': false,
        },
        'games': games,
      }),
    );
    stdout.writeln(
      'FINISHED game ${n + 1}: ${g.steps} steps, ${g.lines} lines ($reason), baseline ${baseline.steps}/${baseline.lines}, random ${random.steps}/${random.lines}',
    );
  }
  await out.close();
  client.close();
}

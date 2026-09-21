import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/jev_client.dart';
import 'package:agent_arcade_lab/unassisted.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 || !['tetris', 'snake'].contains(args[0])) {
    stderr.writeln(
      'Usage: dart run tool/benchmark_jev_raw.dart tetris|snake OUTPUT [seed=20260921] [limit=500] [url=http://127.0.0.1:8770]',
    );
    exitCode = 64;
    return;
  }
  final kind = args[0], dir = Directory(args[1]);
  final seed = args.length > 2 ? int.parse(args[2]) : 20260921;
  final limit = args.length > 3 ? int.parse(args[3]) : 500;
  if (limit < 1 || limit > 500) throw ArgumentError('Limit must be 1..500');
  if (dir.existsSync()) throw StateError('Refusing to overwrite ${dir.path}');
  dir.createSync(recursive: true);
  final api = JevClient(
    args.length > 4 ? args[4] : 'http://127.0.0.1:8770',
    endpoint: kind == 'tetris' ? '/v1/tool-decision' : '/v1/snake-decision',
  );
  final tetris = StepTetris(seed);
  final snake = SnakeArena(seed, names: const ['JEV']);
  final log = File('${dir.path}/steps.jsonl').openWrite();
  final started = DateTime.now().toUtc().toIso8601String();
  final clock = Stopwatch()..start();
  var decisions = 0, invalid = 0;
  String? model, error;
  var reason = 'step_cap';
  bool getOver() => kind == 'tetris' ? tetris.over : snake.over;
  Map<String, dynamic> snapshot() => kind == 'tetris'
      ? {
          'board': tetris.board,
          'piece': tetris.piece,
          'next': tetris.next,
          'x': tetris.x,
          'y': tetris.y,
          'rotation': tetris.rotation,
          'actions': tetris.actions,
          'pieces': tetris.steps,
          'lines': tetris.lines,
          'score': tetris.score,
          'over': tetris.over,
        }
      : {
          'body': [
            for (final p in snake.snakes.single.body) [p.$1, p.$2],
          ],
          'heading': snake.snakes.single.direction,
          'food': snake.food == null ? null : [snake.food!.$1, snake.food!.$2],
          'frame': snake.frame,
          'score': snake.snakes.single.score,
          'alive': snake.snakes.single.alive,
          'over': snake.over,
          'result': snake.result,
        };
  try {
    while (!getOver() && decisions < limit) {
      final request = kind == 'tetris'
          ? rawTetrisRequest(tetris)
          : rawSnakeRequest(snake, 0);
      // Serialize before advancing: game state contains mutable lists.
      final before = jsonDecode(jsonEncode(snapshot()));
      final response = await api.decide(request);
      decisions++;
      model = response['model'] as String;
      final action = response['choice'];
      if (response['error'] != null ||
          !(request['questions']['move']['criteria'] as Map).containsKey(
            action,
          )) {
        throw StateError('Invalid model response');
      }
      var accepted = true;
      if (kind == 'tetris') {
        accepted = tetris.act(action as String);
      } else {
        snake.advance([action as String]);
      }
      if (!accepted) invalid++;
      log.writeln(
        jsonEncode({
          'step': decisions,
          'request': request,
          'response': response,
          'proposed': action,
          'executed': accepted ? action : null,
          'accepted': accepted,
          'corrected': false,
          'before': before,
          'after': snapshot(),
        }),
      );
      await log.flush();
      if (decisions % 25 == 0 || getOver() || !accepted) {
        stdout.writeln(
          jsonEncode({
            'game': kind,
            'step': decisions,
            'score': snapshot()['score'],
            'over': getOver(),
            'accepted': accepted,
          }),
        );
      }
      if (!accepted) {
        reason = 'invalid_action';
        break;
      }
    }
    if (getOver()) {
      reason = kind == 'tetris'
          ? 'spawn_blocked'
          : snake.food == null
          ? 'board_full'
          : 'collision';
    }
  } catch (e) {
    reason = 'request_error';
    error = e.toString();
    exitCode = 1;
  } finally {
    clock.stop();
    api.close();
    await log.close();
    final summary = {
      'game': kind,
      'mode': 'raw-observation-single-action',
      'seed': seed,
      'step_limit': limit,
      'started_at': started,
      'model': model,
      'decisions': decisions,
      'executed_steps': kind == 'tetris' ? tetris.actions : snake.frame,
      'invalid_actions': invalid,
      'corrections': 0,
      'program_assistance': false,
      'score': snapshot()['score'],
      'over': getOver(),
      'end_reason': reason,
      'survived_500_steps':
          limit == 500 &&
          decisions == 500 &&
          invalid == 0 &&
          !getOver() &&
          error == null,
      'elapsed_seconds': clock.elapsedMilliseconds / 1000,
      'error': error,
      'final_state': snapshot(),
    };
    File(
      '${dir.path}/summary.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    stdout.writeln(jsonEncode(summary));
  }
}

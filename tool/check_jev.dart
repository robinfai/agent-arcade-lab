import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/tetris_assist.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_cycle.dart';
import 'package:agent_arcade_lab/snake_arena_assist.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main() async {
  final records = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> choose(
    String endpoint,
    Map<String, dynamic> request,
  ) async {
    final api = JevClient('http://127.0.0.1:8770', endpoint: endpoint);
    try {
      final result = await api.decide(request);
      if (!(request['questions']['move']['criteria'] as Map).containsKey(
        result['choice'],
      )) {
        throw StateError('Unknown choice');
      }
      records.add({
        'endpoint': endpoint,
        'request': request,
        'response': result,
      });
      return result;
    } finally {
      api.close();
    }
  }

  final tetris = StepTetris(20260921);
  for (var i = 0; i < 3 && !tetris.over; i++) {
    final plans = reachablePlans(tetris);
    final r = await choose(
      i == 1 ? '/v1/land-decision' : '/v1/tool-decision',
      uniformTetrisRequest(plans),
    );
    final plan = plans.singleWhere((p) => p.id == r['choice']);
    for (final action in plan.actions) {
      if (!tetris.act(action)) throw StateError('Invalid tetris action');
    }
  }
  final snake = SnakeArena(20260921, names: ['JEV']);
  final cycle = SnakeCycle(snake);
  for (var i = 0; i < 5 && !snake.over; i++) {
    final r = await choose(
      '/v1/snake-decision',
      cycle.request(diagnostics: true),
    );
    snake.advance([r['choice'] as String]);
  }
  final arena = SnakeArena(20260921, names: ['JEV A', 'JEV B']);
  final assist = ArenaAssist(arena);
  final moves = <String>[];
  for (var i = 0; i < 2; i++) {
    final r = await choose('/v1/snake-decision', assist.request(i));
    moves.add(r['choice'] as String);
  }
  arena.advance(moves);
  final summary = {
    'model': records.first['response']['model'],
    'requests': records.length,
    'tetris_actions': tetris.actions,
    'tetris_score': tetris.score,
    'snake_frames': snake.frame,
    'snake_score': snake.snakes.single.score,
    'arena_frames': arena.frame,
    'correction_enabled': false,
  };
  Directory('reports/jev').createSync(recursive: true);
  File('reports/jev/smoke.json').writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'summary': summary, 'records': records}),
  );
  stdout.writeln(jsonEncode(summary));
}

import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/unassisted.dart';

void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Provide a completed benchmark directory');
  }
  final dir = args.single;
  final summary = jsonDecode(File('$dir/summary.json').readAsStringSync());
  final tetris = StepTetris(summary['seed']);
  final snake = SnakeArena(summary['seed'], names: const ['JEV']);
  final isTetris = summary['game'] == 'tetris';
  var count = 0;
  void same(Object? actual, Object? expected, String label) {
    if (jsonEncode(actual) != jsonEncode(expected)) {
      throw StateError('$label mismatch at step $count');
    }
  }

  for (final line in File('$dir/steps.jsonl').readAsLinesSync()) {
    final row = jsonDecode(line);
    count++;
    same(row['step'], count, 'step');
    same(
      row['request'],
      isTetris ? rawTetrisRequest(tetris) : rawSnakeRequest(snake, 0),
      'raw request',
    );
    same(row['proposed'], row['response']['choice'], 'model choice');
    same(row['corrected'], false, 'no correction');
    final accepted = isTetris ? tetris.act(row['proposed']) : true;
    if (!isTetris) snake.advance([row['proposed']]);
    same(row['accepted'], accepted, 'accepted');
    same(row['executed'], accepted ? row['proposed'] : null, 'executed');
    final after = row['after'];
    if (isTetris) {
      same(after['board'], tetris.board, 'board');
      same(
        [
          after['piece'],
          after['next'],
          after['x'],
          after['y'],
          after['rotation'],
          after['actions'],
          after['pieces'],
          after['lines'],
          after['score'],
          after['over'],
        ],
        [
          tetris.piece,
          tetris.next,
          tetris.x,
          tetris.y,
          tetris.rotation,
          tetris.actions,
          tetris.steps,
          tetris.lines,
          tetris.score,
          tetris.over,
        ],
        'tetris state',
      );
    } else {
      same(after['body'], [
        for (final p in snake.snakes.single.body) [p.$1, p.$2],
      ], 'snake body');
      same(
        after['food'],
        snake.food == null ? null : [snake.food!.$1, snake.food!.$2],
        'food',
      );
      same(
        [
          after['heading'],
          after['frame'],
          after['score'],
          after['alive'],
          after['over'],
          after['result'],
        ],
        [
          snake.snakes.single.direction,
          snake.frame,
          snake.snakes.single.score,
          snake.snakes.single.alive,
          snake.over,
          snake.result,
        ],
        'snake state',
      );
    }
  }
  same(summary['decisions'], count, 'decision count');
  same(
    summary['executed_steps'],
    isTetris ? tetris.actions : snake.frame,
    'executed steps',
  );
  same(
    summary['score'],
    isTetris ? tetris.score : snake.snakes.single.score,
    'score',
  );
  same(summary['over'], isTetris ? tetris.over : snake.over, 'over');
  same(summary['program_assistance'], false, 'assistance');
  same(summary['corrections'], 0, 'corrections');
  if (count > summary['step_limit']) throw StateError('Step cap exceeded');
  stdout.writeln(
    'Verified ${summary['game']}: $count raw requests, unchanged choices, exact replay; score=${summary['score']}, over=${summary['over']}.',
  );
}

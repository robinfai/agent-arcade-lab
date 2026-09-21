import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_arena_assist.dart';
import 'package:agent_arcade_lab/unassisted.dart';

void main() {
  test('raw Tetris keeps blocked actions and omits predicted outcomes', () {
    final g = StepTetris(20260921)..x = 0;
    final request = rawTetrisRequest(g);
    final state = request['state'] as Map;
    final criteria = request['questions']['move']['criteria'] as Map;
    expect(criteria.keys, ['left', 'right', 'rotate', 'down', 'hard_drop']);
    expect(g.target('left'), isNull);
    expect(state['board'], hasLength(20));
    expect(state['active']['cells'], g.cells);
    expect(state.keys, isNot(contains('worked_scoring_examples')));
    expect(jsonEncode(request), isNot(contains('holes_after')));
    expect(jsonEncode(criteria), isNot(contains('Best')));
    expect(g.act('left'), false);
    expect(g.actions, 0);
  });
  test(
    'raw Snake exposes coordinates, keeps fatal options and does not reset spawn',
    () {
      final g = SnakeArena(20260921, names: const ['JEV']);
      g.snakes.single.body = [(11, 5), (10, 5), (9, 5)];
      final food = g.food;
      final request = rawSnakeRequest(g, 0);
      expect(request['state']['snakes'][0]['body_head_to_tail'][0], [11, 5]);
      expect(request['questions']['move']['criteria'].keys, [
        'forward',
        'left',
        'right',
      ]);
      expect(g.food, food);
      g.advance(['forward']);
      expect(g.over, true);
      expect(g.snakes.single.score, 0);
    },
  );
  test(
    'mixed arena corrects assisted player but never replaces JEV action',
    () {
      final g = SnakeArena(7);
      g.snakes[0].body = [(11, 5), (10, 5), (9, 5)];
      g.snakes[0].direction = 1;
      g.snakes[1].body = [(0, 7), (1, 7), (2, 7)];
      g.snakes[1].direction = 3;
      final assist = ArenaAssist(g);
      final actions = assist.execute(['forward', 'forward'], unassisted: {0});
      expect(actions[0], 'forward');
      expect(actions[1], isNot('forward'));
      expect(assist.corrections, [0, 1]);
      g.advance(actions);
      expect(g.snakes[0].alive, false);
      expect(g.snakes[1].alive, true);
    },
  );
}

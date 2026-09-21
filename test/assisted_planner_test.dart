import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';

void main() {
  test(
    'Direct target matches the complete step path and rejects unknown ids',
    () {
      final direct = StepTetris(17), step = StepTetris(17);
      final plan = reachablePlans(direct).last;
      for (final action in plan.actions) {
        expect(step.act(action), true);
      }
      expect(landAtTarget(direct, plan.id), plan.actions.length);
      expect(direct.board, step.board);
      expect(direct.piece, step.piece);
      expect(direct.next, step.next);
      expect(direct.score, step.score);
      expect(direct.actions, step.actions);
      final before = direct.board.map((r) => List.of(r)).toList();
      expect(() => landAtTarget(direct, 'unknown'), throwsStateError);
      expect(direct.board, before);
    },
  );

  test('Every offered path executes legally and matches predicted outcome', () {
    for (final piece in shapes.keys) {
      final source = StepTetris(7)..piece = piece;
      source.board[19][4] = 1;
      source.board[18][4] = 1;
      for (final plan in reachablePlans(source)) {
        final g = StepTetris(7)..piece = piece;
        g.board = source.board.map((r) => List<int>.from(r)).toList();
        for (var i = 0; i < plan.actions.length; i++) {
          expect(g.steps, 0);
          expect(g.act(plan.actions[i]), true);
        }
        expect(g.steps, 1);
        expect(g.lines, plan.outcome['lines_cleared']);
        expect(g.over, plan.outcome['game_over']);
      }
    }
  });
  test('Rotation plus translation can reach and clear a narrow well', () {
    final g = StepTetris(9)
      ..piece = 'I'
      ..x = 3
      ..y = 12;
    for (var row = 16; row < 20; row++) {
      g.board[row] = List.generate(10, (col) => col == 8 ? 0 : 1);
    }
    final winners = reachablePlans(
      g,
    ).where((p) => p.outcome['lines_cleared'] == 4);
    // At this height insufficient steps remain to reach column 8 before collision.
    expect(winners, isEmpty);
    g.y = 0;
    final reachable = reachablePlans(
      g,
    ).where((p) => p.outcome['lines_cleared'] == 4);
    expect(reachable, isNotEmpty);
    expect(reachable.first.actions, contains('rotate'));
    expect(reachable.first.actions, contains('right'));
  });
}

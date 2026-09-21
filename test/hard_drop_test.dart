import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/game.dart';

void main() {
  test('hard_drop matches repeated down but counts as one action', () {
    final direct = StepTetris(5), stepped = StepTetris(5);
    final row = direct.actionOptions()['hard_drop']['row_after_step'];
    expect(row, direct.ghost!.y);
    expect(direct.actionOptions()['hard_drop']['locks_piece'], true);
    expect(direct.act('hard_drop'), true);
    while (stepped.steps == 0) {
      stepped.act('down');
    }
    expect(direct.board, stepped.board);
    expect(direct.score, stepped.score);
    expect(direct.next, stepped.next);
    expect(direct.actions, 1);
    expect(direct.steps, 1);
  });
  test('earlier inputs execute before hard_drop; later inputs do not', () {
    final batched = StepTetris(5), expected = StepTetris(5);
    for (final action in ['right', 'rotate', 'hard_drop']) {
      expected.act(action);
    }
    final turn = TurnExecutor(batched, [
      'right',
      'rotate',
      'hard_drop',
      'left',
    ]);
    while (turn.advance()) {}
    expect(turn.executed, 3);
    expect(turn.stopReason, 'piece_locked');
    expect(batched.board, expected.board);
    expect(batched.x, 3);
  });
}

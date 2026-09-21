import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/game.dart';

void main() {
  test('sequence applies in order with one gravity per action', () {
    final g = StepTetris(0)..piece = 'T';
    final t = TurnExecutor(g, ['left', 'rotate', 'down', 'right']);
    while (t.advance()) {}
    expect((g.x, g.y, g.rotation, g.actions), (3, 4, 1, 4));
    expect(t.stopReason, 'plan_complete');
  });
  test('lock discards actions for next piece', () {
    final g = StepTetris(0)
      ..piece = 'O'
      ..y = 18;
    final t = TurnExecutor(g, ['down', 'left', 'rotate']);
    while (t.advance()) {}
    expect((g.steps, g.actions, g.x, g.y), (1, 1, 3, 0));
    expect(t.executed, 1);
    expect(t.stopReason, 'piece_locked');
  });
  test('illegal input stops sequence without fallback', () {
    final g = StepTetris(0)..x = 0;
    final t = TurnExecutor(g, ['left', 'down']);
    expect(t.advance(), false);
    expect(g.actions, 0);
    expect(t.stopReason, 'invalid_action');
  });
  test('plans have bounded size and known actions', () {
    expect(
      () => TurnExecutor(StepTetris(0), List.filled(9, 'down')),
      throwsArgumentError,
    );
    expect(() => TurnExecutor(StepTetris(0), ['drop']), throwsArgumentError);
  });
}

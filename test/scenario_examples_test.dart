import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/scenario_examples.dart';

void main() {
  for (final example in scoringScenarios['examples'] as List) {
    test(
      'scoring example ${example['name']} executes exactly as described',
      () {
        final active = example['active'] as Map;
        final g = StepTetris(1)
          ..piece = active['piece']
          ..next = example['next_piece']
          ..x = active['column']
          ..y = active['row']
          ..rotation = active['rotation'];
        for (final entry in (example['board_rows'] as Map).entries) {
          g.board[int.parse(entry.key)] = (entry.value as String)
              .split('')
              .map((c) => c == '#' ? 1 : 0)
              .toList();
        }
        expect(g.cells, active['cells']);
        expect(g.fits(g.cells, g.x, g.y), true);
        final result = example['result'] as Map;
        final target = example['target'] as Map;
        expect(
          reachablePlans(g).any(
            (p) =>
                p.outcome['column'] == target['column'] &&
                p.outcome['rotation'] == target['rotation'] &&
                p.outcome['lines_cleared'] == result['lines_cleared'],
          ),
          true,
        );
        final actions = List<String>.from(example['actions']);
        final turn = TurnExecutor(g, actions);
        while (turn.advance()) {}
        expect(turn.executed, actions.length);
        expect(turn.stopReason, 'piece_locked');
        expect(g.steps, 1);
        expect(g.lines, result['lines_cleared']);
        expect(g.score, result['score_delta']);
        expect(g.over, result['game_over']);
      },
    );
  }
  test('both live request modes include the verified examples', () {
    final g = StepTetris(1);
    expect(
      g.actionRequest()['state']['worked_scoring_examples'],
      scoringScenarios,
    );
    expect(
      assistedRequest(g, reachablePlans(g))['state']['worked_scoring_examples'],
      scoringScenarios,
    );
  });
}

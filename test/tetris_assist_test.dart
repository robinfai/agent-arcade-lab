import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/tetris_assist.dart';
import 'package:agent_arcade_lab/game.dart';

ReachablePlan plan(
  String id, {
  bool over = false,
  int lines = 0,
  int holes = 0,
  int height = 2,
}) => ReachablePlan(
  id,
  ['hard_drop'],
  {
    'game_over': over,
    'lines_cleared': lines,
    'holes_after': holes,
    'max_height': height,
    'height_sum': height * 4,
    'roughness': 2,
  },
);
void main() {
  test('Survival precedes clears, then holes precede height', () {
    expect(
      bestPlacement([plan('dead', over: true, lines: 4), plan('live')]).id,
      'live',
    );
    expect(
      bestPlacement([
        plan('flat'),
        plan('clear', lines: 1, holes: 2, height: 8),
      ]).id,
      'clear',
    );
    expect(
      bestPlacement([plan('hole', holes: 1), plan('tall', height: 8)]).id,
      'tall',
    );
  });
  test(
    'Correction is explicit, disabled and tied choices remain unchanged',
    () {
      final plans = [plan('bad', holes: 2), plan('good'), plan('tie')];
      final fixed = correctPlacement(plans, {'choice': 'bad'}, enabled: true);
      expect(fixed['raw_choice'], 'bad');
      expect(fixed['choice'], 'good');
      expect(fixed['correction_reason'], '减少封闭空洞');
      expect(
        correctPlacement(plans, {'choice': 'bad'}, enabled: false)['choice'],
        'bad',
      );
      expect(
        correctPlacement(plans, {'choice': 'tie'}, enabled: true)['corrected'],
        false,
      );
      expect(
        () => correctPlacement(plans, {'choice': 'unknown'}, enabled: true),
        throwsStateError,
      );
      expect(
        correctPlacement(plans, {
          'error': 'unavailable',
        }, enabled: true)['error'],
        'unavailable',
      );
    },
  );
  test(
    'Common request preserves all candidates; target execution matches prediction',
    () {
      final game = StepTetris(20260921);
      final plans = reachablePlans(game);
      final request = uniformTetrisRequest(plans);
      expect(
        (request['questions']['move']['criteria'] as Map).keys,
        plans.map((p) => p.id),
      );
      final best = bestPlacement(plans);
      final result = correctPlacement(plans, {
        'choice': plans.last.id,
      }, enabled: true);
      landAtTarget(game, result['choice']);
      expect(game.steps, 1);
      expect(game.lines, best.outcome['lines_cleared']);
      expect(game.over, best.outcome['game_over']);
    },
  );
}

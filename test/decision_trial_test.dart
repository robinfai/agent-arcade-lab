import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/tetris_assist.dart';
import '../tool/decision_trial_core.dart';

void main() {
  test(
    'model requests expose full state but no outcomes or preference labels',
    () {
      for (final game in ['tetris', 'snake']) {
        final trial = DecisionTrial(game, 20260921, 0),
            options = trialOptions(game);
        final text = jsonEncode(options.request);
        for (final forbidden in [
          'holes_after',
          'lines_cleared',
          'roughness',
          'Best placement',
          'Best route',
          'Safe.',
          'predicted_outcomes',
        ]) {
          expect(text.contains(forbidden), false, reason: forbidden);
        }
        final state = options.request['state'] as Map;
        expect(state.containsKey(game == 'tetris' ? 'board' : 'snakes'), true);
        expect(
          options.paths.length,
          game == 'tetris'
              ? reachablePlans(trial.tetris).length
              : trial.legalSnake().length,
        );
      }
    },
  );
  test(
    'permutation changes presentation, not candidate set or baseline choice',
    () {
      for (final game in ['tetris', 'snake']) {
        final a = DecisionTrial(game, 20260921, 0),
            b = DecisionTrial(game, 20260921, 1);
        final x = a.options(), y = b.options();
        expect(a.snapshot(), b.snapshot());
        expect(x.canonical.values.toSet(), y.canonical.values.toSet());
        for (final policy in ['program', 'random']) {
          expect(
            x.canonical[a.baseline(x, policy)],
            y.canonical[b.baseline(y, policy)],
          );
        }
        expect(jsonEncode(x.canonical), isNot(jsonEncode(y.canonical)));
      }
    },
  );
  test('worse legal Tetris placement is executed without correction', () {
    final trial = DecisionTrial('tetris', 20260921, 0);
    final plans = reachablePlans(trial.tetris),
        best = bestPlacement(reachablePlans(trial.tetris));
    final worse = plans.firstWhere((p) => comparePlacements(p, best) > 0);
    final options = trial.options();
    final choice = options.canonical.entries
        .singleWhere((e) => e.value == worse.id)
        .key;
    expect(trial.execute(options, choice, 2000), worse.actions);
    expect(trial.tetris.steps, 1);
  });
  test('future-unsafe but immediately legal snake move remains selectable', () {
    final trial = DecisionTrial('snake', 20260921, 0);
    final move = trial.cycle.moves().firstWhere((m) => m.legal && !m.safe);
    final options = trial.options();
    final choice = options.canonical.entries
        .singleWhere((e) => e.value == move.action)
        .key;
    expect(trial.execute(options, choice, 2000), [move.action]);
  });
  test('hard cap truncates a placement path without completing it', () {
    final trial = DecisionTrial('tetris', 20260921, 0),
        options = trialOptions('tetris');
    final choice = options.paths.entries
        .firstWhere((e) => e.value.length > 1)
        .key;
    expect(trial.execute(options, choice, 1).length, 1);
    expect(trial.steps, 1);
  });
  test('unknown choice is rejected without mutating game state', () {
    final trial = DecisionTrial('snake', 20260921, 0),
        before = trialOptions('snake');
    final snapshot = trial.snapshot();
    expect(() => trial.execute(before, 'unknown', 2000), throwsStateError);
    expect(trial.snapshot(), snapshot);
  });
  test('legal filter leaves no action in a genuinely trapped state', () {
    final trial = DecisionTrial('snake', 20260921, 0);
    trial.snake.snakes.single.body = [(0, 0), (1, 0), (1, 1), (0, 1), (0, 2)];
    trial.snake.food = (8, 8);
    expect(trial.options().paths, isEmpty);
  });
}

DecisionOptions trialOptions(String game) =>
    DecisionTrial(game, 20260921, 0).options();

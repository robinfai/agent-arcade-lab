import 'scenario_examples.dart';
import 'dart:collection';
import 'dart:math';
import 'game.dart';

/// Enumerates reachable locks using the same input-then-gravity rules as play.
/// Does not select or rank plans: Qwen chooses among all resulting placements.
class ReachablePlan {
  final String id;
  final List<String> actions;
  final Map<String, dynamic> outcome;
  ReachablePlan(this.id, this.actions, this.outcome);
}

List<ReachablePlan> reachablePlans(StepTetris g) {
  if (g.over) return [];
  final rs = rotations(g.piece);
  final queue = Queue<(int, int, int, List<String>)>()
    ..add((g.x, g.y, g.rotation, <String>[]));
  final seen = <String>{'${g.x},${g.y},${g.rotation}'};
  final locks = <String>{};
  final plans = <ReachablePlan>[];
  while (queue.isNotEmpty) {
    final s = queue.removeFirst();
    for (final action in ['down', 'left', 'right', 'rotate']) {
      final x =
          s.$1 +
          (action == 'left'
              ? -1
              : action == 'right'
              ? 1
              : 0);
      final r = action == 'rotate' ? (s.$3 + 1) % rs.length : s.$3;
      if (!g.fits(rs[r], x, s.$2)) continue;
      final path = [...s.$4, action];
      if (g.fits(rs[r], x, s.$2 + 1)) {
        if (seen.add('$x,${s.$2 + 1},$r')) {
          queue.add((x, s.$2 + 1, r, path));
        }
        continue;
      }
      if (!locks.add('$x,${s.$2},$r')) continue;
      var b = g.board.map((row) => List<int>.from(row)).toList();
      for (final c in rs[r]) {
        b[s.$2 + c[1]][x + c[0]] = 1;
      }
      final lines = b.where((row) => row.every((v) => v != 0)).length;
      b = b.where((row) => row.any((v) => v == 0)).toList();
      b.insertAll(0, List.generate(lines, (_) => List.filled(width, 0)));
      final heights = List.filled(width, 0);
      var holes = 0;
      for (var col = 0; col < width; col++) {
        var filled = false;
        for (var row = 0; row < height; row++) {
          if (b[row][col] != 0) {
            if (!filled) heights[col] = height - row;
            filled = true;
          } else if (filled) {
            holes++;
          }
        }
      }
      final over = rotations(g.next)[0].any((c) => b[c[1]][3 + c[0]] != 0);
      while (path.isNotEmpty && path.last == 'down') {
        path.removeLast();
      }
      if (action == 'down') {
        path.add('hard_drop');
      }
      plans.add(
        ReachablePlan('p${plans.length}', path, {
          'column': x,
          'rotation': r,
          'row': s.$2,
          'lines_cleared': lines,
          'holes_after': holes,
          'height_sum': heights.reduce((a, b) => a + b),
          'max_height': heights.reduce(max),
          'roughness': List.generate(
            width - 1,
            (i) => (heights[i] - heights[i + 1]).abs(),
          ).reduce((a, b) => a + b),
          'game_over': over,
        }),
      );
    }
  }
  return plans;
}

Map<String, dynamic> assistedRequest(
  StepTetris g,
  List<ReachablePlan> plans,
) => {
  'model': 'jev-latest',
  'state': {
    'worked_scoring_examples': scoringScenarios,
    'game':
        'Step Tetris, assisted planning. Engine enumerates ALL reachable placements and predicts their outcomes. You select; engine executes the selected legal path with step gravity, not hard drop.',
    'piece': g.piece,
    'next_piece': g.next,
  },
  'questions': {
    'move': {
      'type': 'choice',
      'instructions':
          '''Your goal is to survive and score by completing horizontal rows. A row disappears ONLY when all 10 columns are occupied. Clearing rows frees space for future pieces; merely making a flat surface or placing more pieces does not score.
Compare candidates in this strict priority order:
1. Avoid game_over=true whenever any non-terminal candidate exists.
2. Among non-terminal candidates, FIRST maximize lines_cleared. Take an available clear now; do not reject it merely because another placement has a lower height_sum or roughness. Do not delay an available clear to wait for a future multi-line clear.
3. If lines_cleared is tied, prefer fewer holes_after. Holes are empty cells trapped below blocks: they obstruct completing lower rows. Preserve access to gaps instead of roofing them over.
4. Only after comparing clears and holes, prefer lower max_height, then height_sum, then roughness. Flatness is a tie-breaker, NOT the main objective.
When no row can be cleared now, work toward filling incomplete rows while keeping gaps reachable. These candidate summaries do not expose exact row occupancy, so do not invent a nearly completed row or infer it from roughness; use the supplied clear, hole and height measurements.
$scoringExamples
Read the numeric outcomes and apply the priorities before calling the tool. Candidate order is NOT a ranking. Return the label of the best outcome.''',
      'criteria': {for (final p in plans) p.id: p.outcome},
    },
  },
};

/// Executes an already reachable target in one UI update, preserving game rules.
int landAtTarget(StepTetris game, String id) {
  final plan = reachablePlans(game).where((p) => p.id == id).firstOrNull;
  if (plan == null) throw StateError('Unreachable target: $id');
  final before = game.steps;
  for (final action in plan.actions) {
    if (game.steps != before || !game.act(action)) {
      throw StateError('Reachable path diverged');
    }
  }
  if (game.steps != before + 1) throw StateError('Target did not lock');
  return plan.actions.length;
}

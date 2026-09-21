import 'assisted_planner.dart';

// Model-independent one-piece heuristic, not a guarantee of optimal long-term play.
int comparePlacements(ReachablePlan a, ReachablePlan b) {
  final x = a.outcome, y = b.outcome;
  final left = [
    x['game_over'] == true ? 1 : 0,
    -(x['lines_cleared'] as int),
    x['holes_after'] as int,
    x['max_height'] as int,
    x['height_sum'] as int,
    x['roughness'] as int,
  ];
  final right = [
    y['game_over'] == true ? 1 : 0,
    -(y['lines_cleared'] as int),
    y['holes_after'] as int,
    y['max_height'] as int,
    y['height_sum'] as int,
    y['roughness'] as int,
  ];
  for (var i = 0; i < left.length; i++) {
    final c = left[i].compareTo(right[i]);
    if (c != 0) {
      return c;
    }
  }
  return 0;
}

ReachablePlan bestPlacement(List<ReachablePlan> plans) =>
    plans.reduce((a, b) => comparePlacements(a, b) <= 0 ? a : b);
Map<String, dynamic> uniformTetrisRequest(List<ReachablePlan> plans) {
  final best = bestPlacement(plans);
  return {
    'model': 'jev-latest',
    'state':
        'Tetris planner assistance. Complete all ten cells in a row to clear it. The program compares survival, rows cleared, trapped holes, maximum height, total height, then roughness. Best means the best one-piece prediction, not guaranteed future survival. All reachable candidates are included.',
    'questions': {
      'move': {
        'type': 'choice',
        'instructions':
            'Choose the best safe placement. Clear rows and avoid trapped holes. Return the label of the best outcome.',
        'criteria': {
          for (final p in plans)
            p.id: p.outcome['game_over'] == true
                ? 'Unsafe. Game ends.'
                : comparePlacements(p, best) == 0
                ? 'Safe. Best placement. Clear ${p.outcome['lines_cleared']} rows; holes ${p.outcome['holes_after']}.'
                : 'Safe now. Less progress. Clear ${p.outcome['lines_cleared']} rows; holes ${p.outcome['holes_after']}; peak ${p.outcome['max_height']}.',
        },
      },
    },
  };
}

Map<String, dynamic> correctPlacement(
  List<ReachablePlan> plans,
  Map<String, dynamic> result, {
  required bool enabled,
}) {
  if (result['error'] != null) {
    return result;
  }
  final proposed = plans.where((p) => p.id == result['choice']).firstOrNull;
  if (proposed == null) {
    throw StateError('Model selected unknown plan');
  }
  final best = bestPlacement(plans);
  final changed = enabled && comparePlacements(best, proposed) < 0;
  final chosen = changed ? best : proposed;
  var reason = '原样执行';
  if (changed) {
    for (final field in [
      'game_over',
      'lines_cleared',
      'holes_after',
      'max_height',
      'height_sum',
      'roughness',
    ]) {
      if (best.outcome[field] != proposed.outcome[field]) {
        reason = {
          'game_over': '避免立即结束',
          'lines_cleared': '优先消行',
          'holes_after': '减少封闭空洞',
          'max_height': '降低最高列',
          'height_sum': '降低总高度',
          'roughness': '减少表面起伏',
        }[field]!;
        break;
      }
    }
  }
  return {
    ...result,
    'raw_choice': proposed.id,
    'raw_outcome': proposed.outcome,
    'choice': chosen.id,
    'executed_choice': chosen.id,
    'corrected': changed,
    'correction_reason': reason,
    'assistance_enabled': enabled,
  };
}

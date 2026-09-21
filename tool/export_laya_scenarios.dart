import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/scenario_examples.dart';

void main() {
  final cases = <Map<String, dynamic>>[];
  for (final example in scoringScenarios['examples'] as List) {
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
    cases.add({
      'name': example['name'],
      'expected_lines': example['result']['lines_cleared'],
      'request': assistedRequest(g, reachablePlans(g)),
    });
  }
  File('reports/laya/scenarios.json').writeAsStringSync(jsonEncode(cases));
}

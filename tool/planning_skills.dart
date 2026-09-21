import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main() async {
  final api = JevClient('http://127.0.0.1:8765', endpoint: '/v1/tool-decision');
  final records = [];
  try {
    for (final gap in [0, 2, 5, 8, 9]) {
      final g = StepTetris(7)..piece = 'I';
      for (var row = 16; row < 20; row++) {
        g.board[row] = List.generate(10, (col) => col == gap ? 0 : 1);
      }
      final plans = reachablePlans(g);
      final request = assistedRequest(g, plans);
      final response = await api.decide(request);
      final selected = plans
          .where((p) => p.id == response['choice'])
          .firstOrNull;
      if (selected != null) landAtTarget(g, selected.id);
      records.add({
        'gap': gap,
        'request': request,
        'response': response,
        'plan': selected?.actions,
        'lines': g.lines,
        'score': g.score,
        'passed': g.lines == 4,
      });
      File(
        'reports/planning-study/skills.json',
      ).writeAsStringSync(jsonEncode(records));
      stdout.writeln(
        jsonEncode({'gap': gap, 'passed': g.lines == 4, 'score': g.score}),
      );
    }
  } finally {
    api.close();
  }
}

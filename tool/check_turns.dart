import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main() async {
  final api = JevClient('http://127.0.0.1:8765', endpoint: '/v1/turn');
  final g = StepTetris(20260920);
  final records = <Map<String, dynamic>>[];
  try {
    for (var n = 0; n < 3 && !g.over; n++) {
      final request = g.actionRequest(), response = await api.decide(request);
      final record = <String, dynamic>{'turn': n + 1, 'request': request, 'response': response};
      records.add(record);
      if (response['error'] != null) {
        File(
          'reports/qwen4b/turn-smoke.json',
        ).writeAsStringSync(jsonEncode(records));
        throw StateError(response['error']);
      }
      final execution = TurnExecutor(g, List<String>.from(response['actions']));
      while (execution.advance()) {}
      record.addAll({
        'executed': execution.executed,
        'stop_reason': execution.stopReason,
        'actions': g.actions,
        'pieces': g.steps,
        'lines': g.lines,
        'board': g.board,
        'active': {
          'piece': g.piece,
          'x': g.x,
          'y': g.y,
          'rotation': g.rotation,
        },
      });
      File(
        'reports/qwen4b/turn-smoke.json',
      ).writeAsStringSync(jsonEncode(records));
      stdout.writeln(
        jsonEncode({
          'turn': n + 1,
          'plan': response['actions'],
          'executed': execution.executed,
          'reason': execution.stopReason,
          'pieces': g.steps,
        }),
      );
    }
  } finally {
    api.close();
  }
}

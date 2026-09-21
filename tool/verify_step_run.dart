import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';

void main(List<String> args) {
  final dir = args.isEmpty ? 'reports/step-game-first' : args[0];
  final games = <int, StepTetris>{};
  var count = 0, lateral = 0;
  for (final line in File('$dir/actions.jsonl').readAsLinesSync()) {
    final r = jsonDecode(line);
    final g = games.putIfAbsent(r['seed'], () => StepTetris(r['seed']));
    final request = g.actionRequest();
    if (args.length > 1) {
      (request['questions'] as Map)['move']['instructions'] = File(
        args[1],
      ).readAsStringSync().trim();
    }
    if (jsonEncode(request) != jsonEncode(r['request'])) {
      throw StateError('Input mismatch');
    }
    if (g.actionOptions().containsKey('left') ||
        g.actionOptions().containsKey('right')) {
      lateral++;
    }
    if (!g.act(r['response']['answers']['move']['choice'])) {
      throw StateError('Invalid action');
    }
    if (jsonEncode(g.board) != jsonEncode(r['board']) ||
        g.actions != r['action_number'] ||
        g.steps != r['locked_pieces'] ||
        g.lines != r['lines'] ||
        g.over != r['over'] ||
        jsonEncode({
              'piece': g.piece,
              'x': g.x,
              'y': g.y,
              'rotation': g.rotation,
            }) !=
            jsonEncode(r['active'])) {
      throw StateError('State mismatch');
    }
    count++;
  }
  final summary = jsonDecode(File('$dir/summary.json').readAsStringSync());
  for (final r in summary['games']) {
    final g = games[r['seed']]!;
    if (g.steps != r['locked_pieces'] ||
        g.actions != r['actions'] ||
        g.lines != r['lines'] ||
        (r['end_reason'] == 'spawn_blocked' && !g.over)) {
      throw StateError('Summary mismatch');
    }
  }
  stdout.writeln(
    'Verified $count actions and states; lateral movement offered at $lateral actions.',
  );
}

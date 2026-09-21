import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';

void main(List<String> args) {
  final dir = args.isEmpty ? 'reports/prompt-study/priority' : args[0];
  final data = jsonDecode(File('$dir/benchmark.json').readAsStringSync());
  final games = <int, Tetris>{};
  var count = 0;
  for (final line in File('$dir/steps.jsonl').readAsLinesSync()) {
    final r = jsonDecode(line);
    final g = games.putIfAbsent(r['seed'], () => Tetris(r['seed']));
    final request = g.request(g.candidates());
    request['questions']['move']['instructions'] = data['instructions'];
    if (jsonEncode(request) != jsonEncode(r['request'])) {
      throw StateError('Input drift at seed ${r['seed']} step ${r['step']}');
    }
    g.apply(r['choice']);
    if (jsonEncode(g.board) != jsonEncode(r['board']) ||
        g.lines != r['total_lines'] ||
        g.steps != r['step']) {
      throw StateError('Replay mismatch');
    }
    count++;
  }
  if (games.length != 10) throw StateError('Expected ten games');
  for (final record in data['games']) {
    final g = games[record['seed']]!;
    if (g.steps != record['steps'] ||
        g.lines != record['lines'] ||
        (record['end_reason'] == 'top_out' && g.candidates().isNotEmpty)) {
      throw StateError('Invalid final game');
    }
  }
  stdout.writeln(
    'Verified $count exact requests and replay frames across ${games.length} games. Only instructions overridden; no inference requested.',
  );
}

import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_arena_assist.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main(List<String> args) async {
  final seed = args.isEmpty ? 20260921 : int.parse(args[0]);
  final g = SnakeArena(seed);
  final assist = args.contains('assist') ? ArenaAssist(g) : null;
  final clients = [
    JevClient('http://127.0.0.1:8769', endpoint: '/v1/snake-decision'),
    JevClient('http://127.0.0.1:8765', endpoint: '/v1/snake-decision'),
  ];
  final dir = Directory('${args.length > 1 ? args[1] : 'reports/snake'}/$seed')
    ..createSync(recursive: true);
  final records = <Map<String, dynamic>>[];
  String? error;
  try {
    while (!g.over && g.frame < 150) {
      final requests = [
        for (var i = 0; i < 2; i++) assist?.request(i) ?? g.request(i),
      ];
      final results = await Future.wait([
        for (var i = 0; i < 2; i++) clients[i].decide(requests[i]),
      ]);
      for (final r in results) {
        if (r['error'] != null ||
            !['forward', 'left', 'right'].contains(r['choice'])) {
          throw StateError('Invalid action: ${r['error']}');
        }
      }
      final actions = results.map((r) => r['choice'] as String).toList();
      final executed = assist?.execute(actions) ?? actions;
      g.advance(executed);
      records.add({
        'frame': g.frame,
        'executed': executed,
        'corrections': assist == null ? null : List.of(assist.corrections),
        'requests': requests,
        'responses': results,
        'scores': g.snakes.map((s) => s.score).toList(),
        'over': g.over,
      });
      File('${dir.path}/frames.json').writeAsStringSync(jsonEncode(records));
      stdout.writeln(
        'frame=${g.frame} actions=$actions scores=${g.snakes.map((s) => s.score).toList()} ${g.result}',
      );
    }
  } catch (e) {
    error = e.toString();
  } finally {
    for (final c in clients) {
      c.close();
    }
  }
  final summary = {
    'seed': seed,
    'corrections': assist?.corrections,
    'frames': g.frame,
    'scores': g.snakes.map((s) => s.score).toList(),
    'result': error ?? (g.over ? g.result : '150-frame cap'),
    'error': error,
  };
  File('${dir.path}/summary.json').writeAsStringSync(jsonEncode(summary));
  stdout.writeln(jsonEncode(summary));
}

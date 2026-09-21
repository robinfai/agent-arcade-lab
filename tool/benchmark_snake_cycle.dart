import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_cycle.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main(List<String> args) async {
  final api = JevClient(
    'http://127.0.0.1:8769',
    endpoint: '/v1/snake-decision',
  );
  final dir = Directory('reports/snake-cycle')..createSync(recursive: true);
  try {
    for (final shield in args.contains('raw') ? [false] : [false, true]) {
      final g = SnakeArena(20260921, names: const ['Laya']);
      final c = SnakeCycle(g);
      var corrections = 0;
      final rows = <Map<String, dynamic>>[];
      String? error;
      try {
        while (!g.over && g.frame < 300) {
          final req = c.request(diagnostics: true);
          final r = await api.decide(req);
          final proposed = r['choice'] as String;
          final executed = shield
              ? c.executeChoice(
                  proposed,
                  Map<String, dynamic>.from(r['probabilities']),
                )
              : proposed;
          if (proposed != executed) {
            corrections++;
          }
          g.advance([executed]);
          rows.add({
            'frame': g.frame,
            'proposed': proposed,
            'executed': executed,
            'score': g.snakes.single.score,
            'http_ms': r['_http_ms'],
            'probabilities': r['probabilities'],
            'head': g.snakes.single.body.first.toString(),
          });
        }
      } catch (e) {
        error = e.toString();
      }
      final summary = {
        'shield': shield,
        'frames': g.frame,
        'score': g.snakes.single.score,
        'alive': g.snakes.single.alive,
        'length': g.snakes.single.body.length,
        'interventions': corrections,
        'end_reason': error ?? (g.over ? g.result : 'frame_cap'),
      };
      File(
        '${dir.path}/${shield ? 'guarded' : 'raw'}.json',
      ).writeAsStringSync(jsonEncode({'summary': summary, 'frames': rows}));
      stdout.writeln(jsonEncode(summary));
    }
  } finally {
    api.close();
  }
}

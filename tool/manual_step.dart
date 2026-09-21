import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';

void main(List<String> args) {
  final file = File('reports/astra-step/actions.json');
  final actions = file.existsSync()
      ? List<String>.from(jsonDecode(file.readAsStringSync()))
      : <String>[];
  final g = StepTetris(20260920);
  for (final a in actions) {
    if (!g.act(a)) throw StateError('Replay failed');
  }
  final map = {'l': 'left', 'r': 'right', 't': 'rotate', 'd': 'down'};
  for (final c in args.join('').split('')) {
    if (g.over) break;
    if (c == 'f') {
      final before = g.steps;
      while (!g.over && g.steps == before) {
        g.act('down');
        actions.add('down');
      }
      continue;
    }
    final a = map[c];
    if (a == null || !g.act(a)) {
      stdout.writeln('REJECTED $c at action ${g.actions}');
      break;
    }
    actions.add(a);
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(actions));
  stdout.writeln(
    'ACTIONS ${g.actions} PIECES ${g.steps} LINES ${g.lines} SCORE ${g.score} OVER ${g.over}',
  );
  stdout.writeln(
    'ACTIVE ${g.piece} x${g.x} y${g.y} r${g.rotation} NEXT ${g.next}',
  );
  stdout.writeln('   0123456789');
  for (var y = 0; y < 20; y++) {
    stdout.writeln(
      '${y.toString().padLeft(2)} ${g.board[y].map((v) => v == 0 ? '.' : '#').join()}',
    );
  }
  stdout.writeln('ROTATIONS ${rotations(g.piece)}');
  stdout.writeln('LEGAL ${g.actionOptions()}');
  if (g.over) {
    File('reports/astra-step/summary.json').writeAsStringSync(
      jsonEncode({
        'seed': g.seed,
        'actions': g.actions,
        'locked_pieces': g.steps,
        'lines': g.lines,
        'score': g.score,
        'end_reason': 'spawn_blocked',
        'controller': 'Astra explicit actions, no automated placement policy',
      }),
    );
  }
}

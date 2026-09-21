import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';

int holes(List<List<int>> b) {
  var result = 0;
  for (var x = 0; x < 10; x++) {
    var covered = false;
    for (var y = 0; y < 20; y++) {
      if (b[y][x] != 0) {
        covered = true;
      } else if (covered) {
        result++;
      }
    }
  }
  return result;
}

void main() {
  final dir = Directory('reports/astra-step');
  final actions = List<String>.from(
    jsonDecode(File('${dir.path}/actions.json').readAsStringSync()),
  );
  final expected = jsonDecode(
    File('${dir.path}/summary.json').readAsStringSync(),
  );
  final g = StepTetris(20260920);
  final frames = <Map<String, dynamic>>[], mistakes = <Map<String, dynamic>>[];
  final counts = <String, int>{};
  final trace = StringBuffer();
  for (final a in actions) {
    final request = g.actionRequest(),
        before = g.steps,
        oldHoles = holes(g.board),
        piece = g.piece;
    if (!g.act(a)) throw StateError('Illegal action at ${g.actions}');
    counts[a] = (counts[a] ?? 0) + 1;
    final f = {
      'action_number': g.actions,
      'locked_pieces': g.steps,
      'lines': g.lines,
      'choice': a,
      'board': g.board,
      'active': {'piece': g.piece, 'x': g.x, 'y': g.y, 'rotation': g.rotation},
      'over': g.over,
    };
    trace.writeln(
      jsonEncode({
        ...f,
        'request': request,
        'controller': 'Astra explicit selection',
      }),
    );
    if (g.steps != before) {
      frames.add({...f, 'piece': piece, 'holes': holes(g.board)});
      if (holes(g.board) > oldHoles) {
        mistakes.add({
          'piece_number': g.steps,
          'piece': piece,
          'holes_added': holes(g.board) - oldHoles,
        });
      }
    }
  }
  if (!g.over ||
      g.steps != expected['locked_pieces'] ||
      g.lines != expected['lines'] ||
      g.actions != expected['actions'] ||
      g.score != expected['score']) {
    throw StateError('Summary mismatch');
  }
  File('${dir.path}/trace.jsonl').writeAsStringSync(trace.toString());
  File('${dir.path}/replay.json').writeAsStringSync(
    jsonEncode({
      'rules': 'step-gravity-no-kicks',
      'seed': g.seed,
      'frames': frames,
    }),
  );
  File('${dir.path}/validation.json').writeAsStringSync(
    jsonEncode({
      'verified_actions': g.actions,
      'locked_pieces': g.steps,
      'lines': g.lines,
      'score': g.score,
      'over': g.over,
      'counts': counts,
      'hole_increases': mistakes,
    }),
  );
  stdout.writeln(
    'Verified ${g.actions} actions, ${g.steps} pieces, ${g.lines} lines, ${g.score} score, natural top-out.',
  );
  stdout.writeln(jsonEncode({'counts': counts, 'hole_increases': mistakes}));
}

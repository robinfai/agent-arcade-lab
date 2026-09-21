import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';

void main(List<String> args) {
  final file = File('reports/manual-baseline.json');
  final old = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : {
          'seed': 20260921,
          'actions': <String>[],
          'started': DateTime.now().toUtc().toIso8601String(),
        };
  final actions = List<String>.from(old['actions']);
  final g = Tetris(old['seed'] as int), frames = <Map<String, dynamic>>[];
  void play(String id) {
    final p = g.candidates().singleWhere((p) => p.id == id);
    final piece = g.piece;
    g.apply(id);
    frames.add({
      'step': g.steps,
      'piece': piece,
      'choice': id,
      'board': g.board,
      'total_lines': g.lines,
      'cleared': p.lines,
    });
  }

  for (final a in actions) {
    play(a);
  }
  for (final a in args) {
    play(a);
    actions.add(a);
  }
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      ...old,
      'actions': actions,
      'steps': g.steps,
      'lines': g.lines,
      'score': g.score,
      'end_reason': g.candidates().isEmpty ? 'top_out' : 'in_progress',
      'controller':
          'Codex manually selected each placement; no Qwen API, no heuristic policy',
      'frames': frames,
    }),
  );
  stdout.writeln(
    'STEPS ${g.steps} LINES ${g.lines} SCORE ${g.score} CURRENT ${g.piece} NEXT ${g.next}',
  );
  stdout.writeln('   0123456789');
  for (var y = 0; y < 20; y++) {
    stdout.writeln(
      '${y.toString().padLeft(2)} ${g.board[y].map((v) => v == 0 ? '.' : '#').join()}',
    );
  }
  final rs = rotations(g.piece);
  for (var r = 0; r < rs.length; r++) {
    stdout.writeln('r$r ${rs[r]}');
  }
  stdout.writeln('LEGAL ${g.candidates().map((p) => p.id).join(" ")}');
}

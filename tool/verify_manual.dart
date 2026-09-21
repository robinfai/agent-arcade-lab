import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';

void main() {
  final d = jsonDecode(File('reports/manual-baseline.json').readAsStringSync());
  final g = Tetris(d['seed']);
  final issues = <Map<String, dynamic>>[];
  var priorHoles = 0;
  for (var i = 0; i < (d['actions'] as List).length; i++) {
    final p = g.candidates().singleWhere((p) => p.id == d['actions'][i]);
    if (p.holes > priorHoles) {
      issues.add({
        'step': i + 1,
        'piece': g.piece,
        'action': p.id,
        'holes_added': p.holes - priorHoles,
      });
    }
    priorHoles = p.holes;
    g.apply(p.id);
    if (jsonEncode(g.board) != jsonEncode(d['frames'][i]['board']) ||
        g.lines != d['frames'][i]['total_lines']) {
      throw StateError('Replay mismatch ${i + 1}');
    }
  }
  if (g.candidates().isNotEmpty ||
      g.steps != 114 ||
      g.lines != 29 ||
      g.score != 4300) {
    throw StateError('Invalid final result');
  }
  final summary = {
    'seed': g.seed,
    'steps': g.steps,
    'lines': g.lines,
    'score': g.score,
    'next_piece_at_top_out': g.piece,
    'verified_frames': g.steps,
    'rejected_attempts': d['rejected_attempts'],
    'hole_increases': issues,
    'line_clear_histogram': {
      for (var n = 0; n <= 4; n++)
        '$n': (d['frames'] as List).where((f) => f['cleared'] == n).length,
    },
  };
  File(
    'reports/manual-summary.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
  stdout.writeln(jsonEncode(summary));
}

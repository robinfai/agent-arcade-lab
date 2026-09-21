import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';

StepTetris fixture(String name) {
  final g = StepTetris(20260920);
  if (name.startsWith('clear')) {
    final gap = int.parse(name.split('_')[1]);
    g.piece = 'I';
    g.rotation = 1;
    g.x = gap < 4 ? gap + 1 : gap - 1;
    g.y = 15;
    g.board[19] = List.generate(10, (x) => x == gap ? 0 : 2);
  } else {
    g.piece = 'O';
    g.next = 'O';
    g.x = name == 'survive_right' ? 4 : 2;
    g.y = 0;
    g.board[2][name == 'survive_right' ? 4 : 3] = 2;
  }
  return g;
}

void main(List<String> args) {
  const names = [
    'clear_3',
    'clear_5',
    'survive_left',
    'survive_right',
    'clear_1',
    'clear_8',
  ];
  if (args.isEmpty) {
    final cases = [];
    for (final name in names) {
      final g = fixture(name);
      final good = name.startsWith('clear')
          ? (int.parse(name.split('_')[1]) < 4 ? 'left' : 'right')
          : name.split('_')[1];
      final example = [good, ...List.filled(7, 'down')];
      final e = TurnExecutor(g, example);
      while (e.advance()) {}
      final success = name.startsWith('clear')
          ? g.lines == 1
          : !g.over && g.steps == 0;
      if (!success) throw StateError('Invalid fixture solution $name');
      cases.add({
        'id': name,
        'split': names.indexOf(name) < 4 ? 'development' : 'held_out',
        'request': fixture(name).actionRequest(),
        'expected_first': good,
        'reference_plan': example,
        'reference_lines': g.lines,
        'reference_over': g.over,
      });
    }
    File(
      'reports/thinking-study/fixtures.json',
    ).writeAsStringSync(jsonEncode(cases));
  } else {
    final records = jsonDecode(File(args[0]).readAsStringSync()) as List;
    for (final r in records) {
      final g = fixture(r['id']);
      if (r['response']['error'] != null) {
        r['evaluation'] = {'valid': false, 'success': false};
        continue;
      }
      final e = TurnExecutor(g, List<String>.from(r['response']['actions']));
      while (e.advance()) {}
      r['evaluation'] = {
        'valid': true,
        'executed': e.executed,
        'stop_reason': e.stopReason,
        'lines': g.lines,
        'over': g.over,
        'pieces': g.steps,
        'first_correct': r['response']['actions'][0] == r['expected_first'],
        'success': r['id'].startsWith('clear')
            ? g.lines == 1
            : !g.over && e.executed > 0,
        'active': {'x': g.x, 'y': g.y},
      };
    }
    File(args[0]).writeAsStringSync(jsonEncode(records));
    for (final r in records) {
      stdout.writeln('${r['id']}: ${r['evaluation']}');
    }
  }
}

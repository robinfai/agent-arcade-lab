import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Future<void> main(List<String> args) async {
  final api = JevClient(args.isNotEmpty ? args[0] : 'http://127.0.0.1:8765');
  final count = args.length > 1 ? int.parse(args[1]) : 10;
  final cap = args.length > 2 ? int.parse(args[2]) : 10000;
  final dir = args.length > 3 ? args[3] : 'reports/step-game';
  Directory(dir).createSync(recursive: true);
  final log = File('$dir/actions.jsonl').openWrite();
  final records = <Map<String, dynamic>>[];
  try {
    for (var n = 0; n < count; n++) {
      final game = StepTetris(20260920 + n);
      while (!game.over && game.actions < cap) {
        final request = game.actionRequest();
        if (args.length > 4) {
          (request['questions'] as Map)['move']['instructions'] = File(
            args[4],
          ).readAsStringSync().trim();
        }
        final response = await api.decide(request);
        final action = response['answers']['move']['choice'] as String;
        if (!game.act(action)) throw StateError('Illegal model action $action');
        log.writeln(
          jsonEncode({
            'seed': game.seed,
            'action_number': game.actions,
            'locked_pieces': game.steps,
            'lines': game.lines,
            'request': request,
            'response': response,
            'board': game.board,
            'active': {
              'piece': game.piece,
              'x': game.x,
              'y': game.y,
              'rotation': game.rotation,
            },
            'over': game.over,
          }),
        );
      }
      records.add({
        'seed': game.seed,
        'actions': game.actions,
        'locked_pieces': game.steps,
        'lines': game.lines,
        'end_reason': game.over ? 'spawn_blocked' : 'action_cap',
      });
      await File('$dir/summary.json').writeAsString(
        jsonEncode({
          'rules': 'step-gravity-no-kicks',
          'action_cap': cap,
          'games': records,
        }),
      );
      stdout.writeln(jsonEncode(records.last));
    }
  } finally {
    await log.close();
    api.close();
  }
}

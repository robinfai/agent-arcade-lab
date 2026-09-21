import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/assisted_player.dart';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/jev_client.dart';

class FakeChoice extends JevClient {
  int calls = 0;
  String? choice;
  FakeChoice() : super('http://unused');
  @override
  Future<Map<String, dynamic>> decide(Map<String, dynamic> request) async {
    calls++;
    return {
      'choice':
          choice ??
          (request['questions']['move']['criteria'] as Map).keys.first,
      'model': 'test',
      '_http_ms': 1.0,
    };
  }
}

void main() {
  test('Batches retain a plan; external board changes invalidate it', () async {
    final api = FakeChoice();
    addTearDown(api.close);
    final player = AssistedPlayer(api);
    final g = StepTetris(7);
    api.choice = reachablePlans(g).firstWhere((p) => p.actions.length > 8).id;
    final first = await player.decide(g);
    final execution = TurnExecutor(g, List<String>.from(first['actions']));
    while (execution.advance()) {}
    player.observe(g, execution);
    final second = await player.decide(g);
    expect(api.calls, 1);
    expect(second['continued_plan'], true);
    api.choice = null;
    g.act('down');
    await player.decide(g);
    expect(api.calls, 2);
    player.reset();
    await player.decide(g);
    expect(api.calls, 3);
  });
}

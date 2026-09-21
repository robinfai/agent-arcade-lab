import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_cycle.dart';

void main() {
  test('cycle visits all cells and closes with adjacent steps', () {
    final c = SnakeCycle(SnakeArena(1, names: const ['Laya']));
    expect(c.cycle.toSet().length, 144);
    for (var i = 0; i < c.cycle.length; i++) {
      final a = c.cycle[i], b = c.cycle[(i + 1) % c.cycle.length];
      expect((a.$1 - b.$1).abs() + (a.$2 - b.$2).abs(), 1);
    }
  });
  test('arbitrary safe moves preserve life and eventually fill board', () {
    for (final seed in [1, 2, 3]) {
      final g = SnakeArena(seed, names: const ['Laya']);
      final c = SnakeCycle(g), r = Random(seed);
      while (!g.over && g.frame < 30000) {
        final safe = c.moves().where((m) => m.safe).toList();
        expect(safe, isNotEmpty);
        g.advance([safe[r.nextInt(safe.length)].action]);
        expect(g.snakes.single.alive, true);
      }
      expect(g.snakes.single.body.length, 144);
      expect(g.food, isNull);
    }
  });
  test(
    'shield keeps safe choice and corrects unsafe choice using probabilities',
    () {
      final g = SnakeArena(7, names: const ['Laya']);
      final c = SnakeCycle(g);
      final safe = c.moves().where((m) => m.safe).toList();
      final bad = c.moves().firstWhere((m) => !m.safe).action;
      final probs = {for (final a in SnakeCycle.actions) a: 0.0};
      probs[safe.last.action] = 1;
      expect(c.executeChoice(bad, probs), safe.last.action);
      expect(c.executeChoice(safe.first.action, probs), safe.first.action);
      expect(c.request(diagnostics: true)['questions'].keys, [
        'move',
        'risk',
        'food',
      ]);
      expect(() => SnakeCycle(SnakeArena(1)), throwsArgumentError);
    },
  );
}

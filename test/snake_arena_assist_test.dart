import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_arena_assist.dart';

void main() {
  test('right-turn loop is detected and corrected for both players', () {
    final g = SnakeArena(1)..food = (0, 0);
    final p = ArenaAssist(g);
    for (var n = 0; n < 4; n++) {
      p.request(0);
      p.request(1);
      g.advance(['right', 'right']);
    }
    final corrected = p.execute(['right', 'right']);
    expect(corrected[0], isNot('right'));
    expect(corrected[1], isNot('right'));
    expect(p.corrections, [1, 1]);
    expect(p.reasons.every((r) => r == '打破重复循环'), true);
  });
  test('disabled execution preserves model choices and has no corrections', () {
    final g = SnakeArena(1);
    g.snakes[0].body = [(11, 5), (10, 5), (9, 5)];
    final p = ArenaAssist(g);
    expect(p.execute(['forward', 'right'], enabled: false), [
      'forward',
      'right',
    ]);
    expect(p.corrections, [0, 0]);
    expect(p.execute(['forward', 'right']).first, isNot('forward'));
  });
  test(
    'observing same frame is idempotent and new food clears stale loops',
    () {
      final g = SnakeArena(1);
      final p = ArenaAssist(g);
      p.request(0);
      p.request(1);
      p.request(0);
      expect(p.history.map((h) => h.length), [1, 1]);
      g.advance(['forward', 'forward']);
      g.food = (0, 0);
      p.request(0);
      expect(p.history.map((h) => h.length), [1, 1]);
    },
  );
}

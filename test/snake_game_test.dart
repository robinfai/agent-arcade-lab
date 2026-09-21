import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/main.dart';
import 'package:flutter/material.dart';

void main() {
  test('solo moves, eats and loses without a phantom opponent', () {
    final g = SnakeArena(7, names: const ['Qwen 0.8B'])..food = (4, 5);
    expect(g.snakes.length, 1);
    g.advance(['forward']);
    expect(g.snakes.single.score, 10);
    expect(g.snakes.single.body.length, 4);
    expect(g.request(0)['state'], contains('Single-player'));
    g.snakes.single.body = [(11, 5), (10, 5), (9, 5)];
    expect(g.collisionCount(0, 'forward'), 1);
    expect(
      g.request(0)['questions']['move']['criteria']['forward'],
      'Blocked. Collision.',
    );
    g.advance(['forward']);
    expect(g.over, true);
    expect(g.result, contains('Qwen 0.8B 游戏结束'));
  });
  testWidgets('solo model selector and competition reset correctly', (
    tester,
  ) async {
    await tester.pumpWidget(const TetrisApp());
    await tester.tap(find.text('贪吃蛇'));
    await tester.pump();
    await tester.tap(find.text('单模型独玩'));
    await tester.pump();
    expect(find.text('贪吃蛇 · 单模型独玩'), findsOneWidget);
    expect(find.textContaining('黄色 Qwen'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qwen 0.8B').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('青色 Qwen 0.8B'), findsOneWidget);
    await tester.tap(find.text('多模型竞技'));
    await tester.pump();
    expect(find.textContaining('黄色 Qwen 0.8B'), findsOneWidget);
    expect(find.textContaining('帧数：0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'JEV can be selected independently in solo and both arena slots',
    (tester) async {
      await tester.pumpWidget(const TetrisApp());
      await tester.tap(find.text('贪吃蛇'));
      await tester.pump();
      final selectors = find.byType(DropdownButtonFormField<int>);
      expect(selectors, findsNWidgets(2));
      await tester.tap(selectors.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JEV · 云端').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('青色 JEV · 云端'), findsOneWidget);
      expect(find.textContaining('黄色 Qwen 0.8B'), findsOneWidget);
      await tester.tap(selectors.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JEV · 云端').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('黄色 JEV · 云端'), findsOneWidget);
      await tester.tap(find.text('单模型独玩'));
      await tester.pump();
      expect(selectors, findsOneWidget);
      await tester.tap(selectors);
      await tester.pumpAndSettle();
      await tester.tap(find.text('JEV · 云端').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('青色 JEV · 云端'), findsOneWidget);
      expect(find.textContaining('黄色 JEV · 云端'), findsNothing);
      await tester.tap(find.text('多模型竞技'));
      await tester.pump();
      expect(find.textContaining('青色 JEV · 云端'), findsOneWidget);
      expect(find.textContaining('黄色 JEV · 云端'), findsOneWidget);
      expect(find.textContaining('帧数：0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('one-frame safety labels match actual joint collision outcomes', () {
    for (final food in [(4, 5), (7, 6), (0, 0)]) {
      final base = SnakeArena(1)..food = food;
      for (var i = 0; i < 2; i++) {
        for (final action in ['forward', 'left', 'right']) {
          var collisions = 0;
          for (final other in ['forward', 'left', 'right']) {
            final g = SnakeArena(1)..food = food;
            g.advance(i == 0 ? [action, other] : [other, action]);
            if (!g.snakes[i].alive) {
              collisions++;
            }
          }
          expect(base.collisionCount(i, action), collisions);
        }
        final criteria =
            base.request(i)['questions']['move']['criteria'] as Map;
        expect(criteria.keys, ['forward', 'left', 'right']);
      }
    }
  });
  test('same seed gives same food outside both snakes', () {
    final a = SnakeArena(7), b = SnakeArena(7);
    expect(a.food, b.food);
    expect(a.snakes.expand((s) => s.body).contains(a.food), false);
  });
  test('simultaneous move, eating, growth and respawn', () {
    final g = SnakeArena(1)..food = (4, 5);
    g.advance(['forward', 'forward']);
    expect(g.snakes[0].body.first, (4, 5));
    expect(g.snakes[1].body.first, (7, 6));
    expect(g.snakes[0].score, 10);
    expect(g.snakes[0].body.length, 4);
    expect(g.snakes[1].body.length, 3);
    expect(g.snakes.expand((s) => s.body).contains(g.food), false);
    expect(g.frame, 1);
  });
  test('same-cell heads fail both and award no contested food', () {
    final g = SnakeArena(1)..food = (5, 5);
    g.snakes[0].body = [(4, 5), (3, 5), (2, 5)];
    g.snakes[1].body = [(6, 5), (7, 5), (8, 5)];
    g.advance(['forward', 'forward']);
    expect(g.over, true);
    expect(g.snakes.every((s) => !s.alive), true);
    expect(g.snakes.every((s) => s.score == 0), true);
  });
  test('head swap fails both', () {
    final g = SnakeArena(1);
    g.snakes[0].body = [(4, 5), (3, 5)];
    g.snakes[1].body = [(5, 5), (6, 5)];
    g.advance(['forward', 'forward']);
    expect(g.snakes.every((s) => !s.alive), true);
  });
  test('wall collision and rival body collision lose', () {
    final g = SnakeArena(1);
    g.snakes[0].body = [(11, 5), (10, 5)];
    g.advance(['forward', 'forward']);
    expect(g.snakes[0].alive, false);
    expect(g.snakes[1].alive, true);
    final h = SnakeArena(1);
    h.snakes[0].body = [(7, 5), (6, 5)];
    h.snakes[1].body = [(9, 5), (8, 5), (8, 6)];
    h.snakes[1].direction = 0;
    h.advance(['forward', 'forward']);
    expect(h.snakes[0].alive, false);
  });
  test('vacating tail can be entered, growing tail cannot', () {
    SnakeArena setup() {
      final g = SnakeArena(1);
      g.snakes[0].body = [(5, 5), (4, 5)];
      g.snakes[1].body = [(7, 6), (6, 6), (6, 5)];
      g.snakes[1].direction = 1;
      return g;
    }

    final a = setup()..food = (0, 0);
    a.advance(['forward', 'forward']);
    expect(a.snakes[0].alive, true);
    final b = setup()..food = (8, 6);
    b.advance(['forward', 'forward']);
    expect(b.snakes[0].alive, false);
  });
  test('invalid pair does not partially advance', () {
    final g = SnakeArena(1);
    expect(() => g.advance(['forward', 'bad']), throwsArgumentError);
    expect(g.frame, 0);
    expect(g.snakes[0].body.first, (3, 5));
  });
  testWidgets('switch to arena and reset', (tester) async {
    await tester.pumpWidget(const TetrisApp());
    await tester.tap(find.text('贪吃蛇'));
    await tester.pump();
    expect(find.text('贪吃蛇 · 同帧竞技'), findsOneWidget);
    expect(find.textContaining('黄色 Qwen 0.8B'), findsOneWidget);
    await tester.ensureVisible(find.text('同种子重开'));
    await tester.tap(find.text('同种子重开'));
    await tester.pump();
    expect(find.textContaining('帧数：0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

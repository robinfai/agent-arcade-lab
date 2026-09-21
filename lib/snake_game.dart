import 'dart:math';

typedef Cell = (int, int);

class ArenaSnake {
  List<Cell> body;
  int direction, score = 0;
  bool alive = true;
  ArenaSnake(this.body, this.direction);
}

class SnakeArena {
  static const size = 12;
  static const directions = [(0, -1), (1, 0), (0, 1), (-1, 0)];
  final int seed;
  late final Random random = Random(seed);
  final List<String> names;
  late final List<ArenaSnake> snakes;
  static List<ArenaSnake> initialSnakes() => [
    ArenaSnake([(3, 5), (2, 5), (1, 5)], 1),
    ArenaSnake([(8, 6), (9, 6), (10, 6)], 3),
  ];
  Cell? food;
  int frame = 0;
  bool over = false;
  String result = '';
  SnakeArena(this.seed, {this.names = const ['Laya', 'Qwen 0.8B']}) {
    if (names.isEmpty || names.length > 2) {
      throw ArgumentError('Select one or two players');
    }
    snakes = initialSnakes().take(names.length).toList();
    spawnFood();
  }
  void spawnFood() {
    final occupied = snakes.expand((s) => s.body).toSet();
    final free = <Cell>[
      for (var y = 0; y < size; y++)
        for (var x = 0; x < size; x++)
          if (!occupied.contains((x, y))) (x, y),
    ];
    food = free.isEmpty ? null : free[random.nextInt(free.length)];
    if (food == null) {
      over = true;
      result = '棋盘已满 · 比赛结束';
    }
  }

  int heading(int i, String action) => switch (action) {
    'UP' => 0,
    'RIGHT' => 1,
    'DOWN' => 2,
    'LEFT' => 3,
    'forward' => snakes[i].direction,
    'left' => (snakes[i].direction + 3) % 4,
    'right' => (snakes[i].direction + 1) % 4,
    _ => throw ArgumentError('Unknown action: $action'),
  };
  Cell target(int i, String action) {
    final d = directions[heading(i, action)], h = snakes[i].body.first;
    return (h.$1 + d.$1, h.$2 + d.$2);
  }

  bool outside(Cell p) => p.$1 < 0 || p.$1 >= size || p.$2 < 0 || p.$2 >= size;
  // Evaluate both intents against the same snapshot, then commit together.
  void advance(List<String> actions) {
    if (over) {
      return;
    }
    if (actions.length != snakes.length) {
      throw ArgumentError('Need one action per player');
    }
    final targets = [
      for (var i = 0; i < snakes.length; i++) target(i, actions[i]),
    ];
    final grows = [for (final p in targets) p == food];
    final occupied = <Cell>{
      for (var i = 0; i < snakes.length; i++)
        ...snakes[i].body.take(snakes[i].body.length - (grows[i] ? 0 : 1)),
    };
    final headOn = targets.length > 1 && targets[0] == targets[1];
    final dead = [
      for (final p in targets) outside(p) || occupied.contains(p) || headOn,
    ];
    for (var i = 0; i < snakes.length; i++) {
      snakes[i].direction = heading(i, actions[i]);
      snakes[i].alive = !dead[i];
      if (!dead[i]) {
        snakes[i].body.insert(0, targets[i]);
        if (grows[i]) {
          snakes[i].score += 10;
        } else {
          snakes[i].body.removeLast();
        }
      }
    }
    frame++;
    if (dead.any((d) => d)) {
      over = true;
      result = snakes.length == 1
          ? '${names.first} 游戏结束 · 碰撞失败'
          : dead.every((d) => d)
          ? '平局 · 双方碰撞失败'
          : '${names[dead[0] ? 1 : 0]} 获胜 · 对手碰撞失败';
    } else if (grows.any((g) => g)) {
      spawnFood();
    }
  }

  // Enumerate all three opponent intentions using the same simultaneous collision rules.
  // This is one-frame safety information, not a long-term survival guarantee.
  int collisionCount(int index, String action) {
    final p = target(index, action);
    var count = 0;
    for (final rivalAction
        in snakes.length == 1 ? ['forward'] : ['forward', 'left', 'right']) {
      final targets = List<Cell>.generate(
        snakes.length,
        (i) => target(i, i == index ? action : rivalAction),
      );
      final occupied = <Cell>{
        for (var i = 0; i < snakes.length; i++)
          ...snakes[i].body.take(
            snakes[i].body.length - (targets[i] == food ? 0 : 1),
          ),
      };
      if (outside(p) ||
          occupied.contains(p) ||
          (targets.length > 1 && targets[0] == targets[1])) {
        count++;
      }
    }
    return count;
  }

  Map<String, dynamic> request(int index) {
    const actions = ['forward', 'left', 'right'];
    final risks = {for (final a in actions) a: collisionCount(index, a)};
    final distances = {
      for (final a in actions)
        a: food == null
            ? 0
            : (target(index, a).$1 - food!.$1).abs() +
                  (target(index, a).$2 - food!.$2).abs(),
    };
    final safe = actions.where((a) => risks[a] == 0).toList();
    final bestDistance = safe.isEmpty
        ? null
        : safe.map((a) => distances[a]!).reduce(min);
    return {
      'model': 'jev-latest',
      'state':
          '${snakes.length == 1 ? 'Single-player' : 'Two-player'} Snake. Safe move this frame: ${safe.isNotEmpty ? 'yes' : 'no'}. '
          'All active snakes move simultaneously. Collision loses. Eat food to score 10 and grow. '
          'Left/right turn relative to your heading, then move one cell. '
          'Safe means no collision this frame for any opponent action; future safety is unknown. '
          'Best progress means smallest Manhattan distance among safe moves. No execution shield.',
      'questions': {
        'move': {
          'type': 'choice',
          'instructions':
              'Choose the best safe move toward food. Avoid collisions. Return the label of the best outcome.',
          'criteria': {
            for (final a in actions)
              a: risks[a] == (snakes.length == 1 ? 1 : 3)
                  ? 'Blocked. Collision.'
                  : risks[a]! > 0
                  ? 'Unsafe. Possible opponent collision.'
                  : target(index, a) == food
                  ? 'Safe. Eat food now. Best.'
                  : distances[a] == bestDistance
                  ? 'Safe. Best progress toward food.'
                  : 'Safe. Slower progress toward food.',
          },
        },
      },
    };
  }
}

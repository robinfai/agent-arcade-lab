// Cycle planner and compact descriptions adapted from laya-mlx snake/game.py
// and snake/policy.py (Apache-2.0). Kept separate from the actual game rules.
import 'snake_game.dart';

class CycleMove {
  final String action;
  final bool legal, safe, eats;
  final int advance;
  CycleMove(this.action, this.legal, this.safe, this.eats, this.advance);
}

class SnakeCycle {
  static const actions = ['UP', 'DOWN', 'LEFT', 'RIGHT'];
  final SnakeArena game;
  final List<Cell> cycle = [
    (0, 0),
    for (var y = 0; y < SnakeArena.size; y++)
      for (var i = 1; i < SnakeArena.size; i++)
        (y.isEven ? i : SnakeArena.size - i, y),
    for (var y = SnakeArena.size - 1; y > 0; y--) (0, y),
  ];
  late final indices = {for (var i = 0; i < cycle.length; i++) cycle[i]: i};
  SnakeCycle(this.game) {
    if (game.snakes.length != 1) {
      throw ArgumentError('Cycle shield is solo only');
    }
    final start = indices[(SnakeArena.size ~/ 2, SnakeArena.size ~/ 2)]!;
    final snake = game.snakes.single;
    snake.body = [
      for (var i = 0; i < 3; i++) cycle[(start - i) % cycle.length],
    ];
    final h = snake.body[0], neck = snake.body[1];
    snake.direction = SnakeArena.directions.indexOf((
      h.$1 - neck.$1,
      h.$2 - neck.$2,
    ));
    game.spawnFood();
  }
  List<CycleMove> moves() {
    if (game.over) {
      return [];
    }
    final s = game.snakes.single,
        head = indices[game.snakes.single.body.first]!;
    final tailDistance = (indices[s.body.last]! - head) % cycle.length;
    final foodDistance = (indices[game.food]! - head) % cycle.length;
    return [
      for (final a in actions)
        (() {
          final p = game.target(0, a), eats = p == game.food;
          final legal =
              !game.outside(p) &&
              p != s.body[1] &&
              !s.body.take(s.body.length - (eats ? 0 : 1)).contains(p);
          final advance = ((indices[p] ?? head) - head) % cycle.length;
          final safe =
              legal &&
              advance > 0 &&
              advance <= foodDistance &&
              advance <= tailDistance &&
              !(advance == tailDistance && eats);
          return CycleMove(a, legal, safe, eats, advance);
        })(),
    ];
  }

  bool foodReachable() {
    final blocked = game.snakes.single.body.skip(1).toSet();
    final seen = {game.snakes.single.body.first};
    final queue = seen.toList();
    for (var i = 0; i < queue.length; i++) {
      for (final d in SnakeArena.directions) {
        final p = (queue[i].$1 + d.$1, queue[i].$2 + d.$2);
        if (!game.outside(p) && !blocked.contains(p) && seen.add(p)) {
          queue.add(p);
        }
      }
    }
    return seen.contains(game.food);
  }

  Map<String, dynamic> request({bool diagnostics = false}) {
    final all = moves(), safe = moves().where((m) => m.safe).toList();
    final preferred = safe.isEmpty
        ? null
        : safe.reduce((a, b) => a.advance >= b.advance ? a : b).action;
    return {
      'model': 'jev-latest',
      'state':
          'Safe route: ${safe.isNotEmpty ? 'yes' : 'no'}. Food reachable through empty cells: ${foodReachable() ? 'yes' : 'no'}.',
      'questions': {
        'move': {
          'type': 'choice',
          'instructions': 'Choose the best safe move toward food.',
          'criteria': {
            for (final m in all)
              m.action: !m.legal
                  ? 'Blocked. Collision.'
                  : !m.safe
                  ? 'Unsafe. Traps the snake.'
                  : m.eats
                  ? 'Safe. Eat food now. Best.'
                  : m.action == preferred
                  ? 'Safe. Best route to food.'
                  : 'Safe. Slower route.',
          },
        },
        if (diagnostics)
          'risk': {
            'type': 'noul',
            'instructions': 'Is a safe route available?',
          },
        if (diagnostics)
          'food': {
            'type': 'noul',
            'instructions': 'Is food reachable through empty cells?',
          },
      },
    };
  }

  String executeChoice(String proposed, Map<String, dynamic>? probabilities) {
    if (!actions.contains(proposed)) {
      throw StateError('Invalid model choice');
    }
    final safe = moves().where((m) => m.safe).toList();
    if (safe.isEmpty) {
      throw StateError('Cycle invariant broken; no safe successor');
    }
    if (safe.any((m) => m.action == proposed)) {
      return proposed;
    }
    if (probabilities != null) {
      for (final a in actions) {
        final p = probabilities[a];
        if (p is! num || !p.isFinite || p < 0 || p > 1) {
          throw StateError('Invalid probabilities');
        }
      }
      return safe
          .reduce(
            (a, b) =>
                (probabilities[a.action] as num) >=
                    (probabilities[b.action] as num)
                ? a
                : b,
          )
          .action;
    }
    // Qwen tool calls do not expose a probability distribution.
    return safe.reduce((a, b) => a.advance >= b.advance ? a : b).action;
  }
}

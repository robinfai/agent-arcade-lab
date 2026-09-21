import 'snake_game.dart';

class ArenaOption {
  final String action;
  final int risk, visits, distance, space;
  ArenaOption(this.action, this.risk, this.visits, this.distance, this.space);
}

class ArenaAssist {
  final SnakeArena game;
  final history = <List<String>>[[], []];
  final corrections = [0, 0];
  final reasons = ['—', '—'];
  List<String> raw = ['—', '—'];
  Cell? lastFood;
  int lastObserved = -1;
  ArenaAssist(this.game);
  String pose(int i, Cell p, int heading) => '$p/$heading';
  void observe() {
    if (lastObserved == game.frame) {
      return;
    }
    if (lastFood != game.food) {
      for (final h in history) {
        h.clear();
      }
      lastFood = game.food;
    }
    for (var i = 0; i < 2; i++) {
      history[i].add(
        pose(i, game.snakes[i].body.first, game.snakes[i].direction),
      );
      if (history[i].length > 20) {
        history[i].removeAt(0);
      }
    }
    lastObserved = game.frame;
  }

  List<ArenaOption> options(int i) {
    observe();
    return [
      for (final action in ['forward', 'left', 'right'])
        (() {
          final target = game.target(i, action);
          final blocked = game.snakes.expand((s) => s.body).toSet()
            ..remove(target);
          final distances = <Cell, int>{target: 0}, queue = <Cell>[target];
          if (!game.outside(target)) {
            for (var n = 0; n < queue.length; n++) {
              final p = queue[n];
              for (final d in SnakeArena.directions) {
                final q = (p.$1 + d.$1, p.$2 + d.$2);
                if (!game.outside(q) &&
                    !blocked.contains(q) &&
                    !distances.containsKey(q)) {
                  distances[q] = distances[p]! + 1;
                  queue.add(q);
                }
              }
            }
          }
          final visits = history[i]
              .where((p) => p == pose(i, target, game.heading(i, action)))
              .length;
          return ArenaOption(
            action,
            game.collisionCount(i, action),
            visits,
            distances[game.food] ?? 999,
            queue.length,
          );
        })(),
    ];
  }

  int compare(ArenaOption a, ArenaOption b) {
    for (final pair in [
      (a.risk, b.risk),
      (a.visits, b.visits),
      (a.distance, b.distance),
      (-a.space, -b.space),
    ]) {
      final c = pair.$1.compareTo(pair.$2);
      if (c != 0) {
        return c;
      }
    }
    return 0;
  }

  Map<String, dynamic> request(int i) {
    final opts = options(i), req = game.request(i);
    final best = opts.reduce((a, b) => compare(a, b) <= 0 ? a : b);
    req['state'] =
        'Competitive Snake. Program checks next-frame collision against all opponent actions, recent repeated head/heading positions, and paths to food avoiding both current bodies. Future opponent movement is unknown. All options remain available.';
    req['questions'] = {
      'move': {
        'type': 'choice',
        'instructions':
            'Choose the best safe route to food. Avoid collisions and repeated loops. Return the label of the best outcome.',
        'criteria': {
          for (final o in opts)
            o.action: o.risk == 3
                ? 'Blocked. Collision.'
                : o.risk > 0
                ? 'Risky. Possible opponent collision.'
                : o.visits > 0
                ? 'Safe now. Repeats a recent position; avoid looping.'
                : compare(o, best) == 0
                ? 'Safe. Best available route toward food.'
                : o.distance == 999
                ? 'Safe now. No path to food through current empty cells.'
                : 'Safe. Slower route toward food.',
        },
      },
    };
    return req;
  }

  List<String> execute(List<String> proposals, {bool enabled = true}) {
    if (proposals.length != 2 ||
        proposals.any((a) => !['forward', 'left', 'right'].contains(a))) {
      throw ArgumentError('Invalid actions');
    }
    raw = List.of(proposals);
    final result = List.of(proposals);
    // Both decisions use the unchanged frame; neither model gets privileged treatment.
    for (var i = 0; i < 2; i++) {
      reasons[i] = '原样执行';
      final opts = options(i),
          original = opts.firstWhere((o) => o.action == proposals[i]);
      final best = opts.reduce((a, b) => compare(a, b) <= 0 ? a : b);
      if (enabled &&
          compare(best, original) < 0 &&
          (original.risk > best.risk ||
              original.visits > best.visits ||
              (original.distance == 999 && best.distance < 999))) {
        result[i] = best.action;
        corrections[i]++;
        reasons[i] = original.risk > best.risk
            ? '降低碰撞风险'
            : original.visits > best.visits
            ? '打破重复循环'
            : '恢复食物通路';
      }
    }
    return result;
  }
}

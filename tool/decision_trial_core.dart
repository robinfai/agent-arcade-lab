// Shared legal candidates and execution; policy is the only arm-specific part.
import 'dart:convert';
import 'dart:math';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_cycle.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/tetris_assist.dart';
import 'package:agent_arcade_lab/unassisted.dart';

class DecisionOptions {
  final Map<String, dynamic> request;
  final Map<String, List<String>> paths;
  final Map<String, String> canonical;
  DecisionOptions(this.request, this.paths, this.canonical);
}

class DecisionTrial {
  final String game;
  final int seed, orderSeed;
  late final StepTetris tetris = StepTetris(seed);
  late final SnakeArena snake = SnakeArena(seed, names: const ['model']);
  late final SnakeCycle cycle;
  int decisions = 0;
  DecisionTrial(this.game, this.seed, this.orderSeed) {
    if (!['tetris', 'snake'].contains(game)) throw ArgumentError('game');
    // Same cycle-aligned initial state for ALL policies, including random/model.
    cycle = SnakeCycle(snake);
  }
  int get steps => game == 'tetris' ? tetris.actions : snake.frame;
  int get score => game == 'tetris' ? tetris.score : snake.snakes.single.score;
  bool get over => game == 'tetris' ? tetris.over : snake.over;
  Map<String, dynamic> snapshot() => jsonDecode(
    jsonEncode(
      game == 'tetris'
          ? {
              'board': tetris.board,
              'piece': tetris.piece,
              'next': tetris.next,
              'x': tetris.x,
              'y': tetris.y,
              'rotation': tetris.rotation,
              'actions': tetris.actions,
              'pieces': tetris.steps,
              'lines': tetris.lines,
              'score': score,
              'over': over,
            }
          : {
              'body': [
                for (final c in snake.snakes.single.body) [c.$1, c.$2],
              ],
              'heading': snake.snakes.single.direction,
              'food': snake.food == null
                  ? null
                  : [snake.food!.$1, snake.food!.$2],
              'frame': snake.frame,
              'score': score,
              'alive': snake.snakes.single.alive,
              'over': over,
            },
    ),
  );

  List<String> legalSnake() => SnakeCycle.actions.where((action) {
    final body = snake.snakes.single.body;
    final target = snake.target(0, action);
    final eats = target == snake.food;
    return !snake.outside(target) &&
        target != body[1] &&
        !body.take(body.length - (eats ? 0 : 1)).contains(target);
  }).toList();

  DecisionOptions options() {
    final descriptions = <String, String>{};
    final paths = <String, List<String>>{};
    late Map<String, dynamic> state;
    late String instructions;
    if (game == 'tetris') {
      state = Map<String, dynamic>.from(rawTetrisRequest(tetris)['state']);
      state['next_rotations'] = rotations(tetris.next);
      instructions =
          'Choose one reachable landing to maximize score and survive. '
          'Coordinates start at top-left; x increases right, y down. '
          'Board # cells are locked blocks. Active cells and listed rotations are offsets from their origin. '
          'Each option specifies the origin column, row and rotation index at lock. '
          'The same engine executes a reachable path for every policy, with input then gravity, no wall kicks or hold. '
          'Full rows disappear; clearing 1/2/3/4 rows scores 100/300/500/800. '
          'The next piece spawns at column 3, row 0, rotation 0; overlap ends play. '
          'Infer consequences from the board; no evaluations or preferred options are supplied.';
      for (final p in reachablePlans(tetris)) {
        descriptions[p.id] =
            'Origin column ${p.outcome['column']}, row ${p.outcome['row']}, rotation ${p.outcome['rotation']}.';
        paths[p.id] = p.actions;
      }
    } else {
      state = Map<String, dynamic>.from(rawSnakeRequest(snake, 0)['state']);
      instructions =
          'Choose one absolute direction to maximize food score and survive. '
          'Coordinates start at top-left; x increases right and y down. Body is head to tail. '
          'Move one cell; eating scores 10 and grows the body, otherwise the tail vacates. '
          'Wall or non-vacating body collision ends play. Food respawns in an empty cell. '
          'Only immediately collision-free directions are listed; they can still lead to future traps. '
          'No route, future safety prediction or recommended action is supplied.';
      const meanings = {
        'UP': 'Move up: y minus 1.',
        'DOWN': 'Move down: y plus 1.',
        'LEFT': 'Move left: x minus 1.',
        'RIGHT': 'Move right: x plus 1.',
      };
      for (final action in legalSnake()) {
        descriptions[action] = meanings[action]!;
        paths[action] = [action];
      }
    }
    // Separate presentation RNG: never consumes game or random-policy RNG.
    final rng = Random(orderSeed ^ seed ^ (decisions * 104729));
    final keys = descriptions.keys.toList()..shuffle(rng);
    final aliases = List.generate(keys.length, (i) => 'o$i')..shuffle(rng);
    final mapping = <String, String>{};
    final presented = <String, String>{};
    final presentedPaths = <String, List<String>>{};
    for (var i = 0; i < keys.length; i++) {
      mapping[aliases[i]] = keys[i];
      presented[aliases[i]] = descriptions[keys[i]]!;
      presentedPaths[aliases[i]] = paths[keys[i]]!;
    }
    return DecisionOptions(
      {
        'model': 'jev-latest',
        'state': state,
        'questions': {
          'move': {
            'type': 'choice',
            'instructions': instructions,
            'criteria': presented,
          },
        },
      },
      presentedPaths,
      mapping,
    );
  }

  String baseline(DecisionOptions options, String policy) {
    late String canonical;
    if (policy == 'random') {
      // Selection is independent of candidate presentation permutation.
      final candidates = options.canonical.values.toList()..sort();
      canonical =
          candidates[Random(
            seed ^ 0x515151 ^ (decisions * 65537),
          ).nextInt(candidates.length)];
    } else if (policy == 'program') {
      if (game == 'tetris') {
        canonical = bestPlacement(reachablePlans(tetris)).id;
      } else {
        final safe = cycle.moves().where((m) => m.safe).toList();
        if (safe.isEmpty) {
          throw StateError('Program cycle has no safe successor');
        }
        canonical = safe
            .reduce((a, b) => a.advance >= b.advance ? a : b)
            .action;
      }
    } else {
      throw ArgumentError('policy');
    }
    return options.canonical.entries
        .singleWhere((e) => e.value == canonical)
        .key;
  }

  List<String> execute(DecisionOptions options, String chosen, int cap) {
    if (!options.paths.containsKey(chosen)) throw StateError('Unknown choice');
    final executed = <String>[];
    for (final action in options.paths[chosen]!) {
      if (steps >= cap || over) break;
      if (game == 'tetris') {
        if (!tetris.act(action)) throw StateError('Legal plan rejected');
      } else {
        snake.advance([action]);
      }
      executed.add(action);
    }
    decisions++;
    return executed;
  }
}

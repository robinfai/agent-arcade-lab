import 'scenario_examples.dart';
import 'dart:math';

const width = 10, height = 20;

const scoringExamples =
    r'''SCORING EXAMPLES (teaching examples, not the current candidates):
At ONE lock: 0 cleared rows = +0 points; 1 = +100; 2 = +300; 3 = +500; 4 = +800. Moving, rotating, hard_drop and locking alone earn +0.
Example 1: Both plans have game_over=false. A clears 0 rows (+0), holes_after=0, roughness=1. B clears 1 row (+100), holes_after=2, roughness=8. Choose B: an immediate safe clear takes priority over flatness and holes.
Example 2: Both plans are safe. A clears 1 row (+100), B clears 2 rows (+300). Choose B. If the old total was 200, the new totals would be 300 and 500 respectively.
Example 3: Both plans are safe. A clears 3 rows (+500), B clears 4 rows (+800). Choose B. One four-row clear earns 800; four separate one-row clears earn 400. Still take a clear available now instead of waiting for an uncertain future four-row clear.
Example 4: Both plans are safe and clear 1 row (+100). A leaves 0 holes; B leaves 3 holes. Choose A: equal immediate points, fewer trapped gaps for future rows.
Example 5: A has game_over=false and clears 1 row (+100). B has game_over=true and clears 2 rows (+300 before the game ends). Choose A under the survival-first policy; B's points do not undo game over.
Every example describes outcomes AFTER locking. Locking is normal; game_over=false means the next piece can be played in a NEW turn. Do not infer game over from lines_cleared. Apply the comparisons to the real candidate IDs below; never copy an example's A/B label.''';
const shapes = <String, List<List<int>>>{
  'I': [
    [0, 0],
    [1, 0],
    [2, 0],
    [3, 0],
  ],
  'O': [
    [0, 0],
    [1, 0],
    [0, 1],
    [1, 1],
  ],
  'T': [
    [1, 0],
    [0, 1],
    [1, 1],
    [2, 1],
  ],
  'S': [
    [1, 0],
    [2, 0],
    [0, 1],
    [1, 1],
  ],
  'Z': [
    [0, 0],
    [1, 0],
    [1, 1],
    [2, 1],
  ],
  'J': [
    [0, 0],
    [0, 1],
    [1, 1],
    [2, 1],
  ],
  'L': [
    [2, 0],
    [0, 1],
    [1, 1],
    [2, 1],
  ],
};
List<List<List<int>>> rotations(String piece) {
  var cells = shapes[piece]!.map((p) => List<int>.from(p)).toList();
  final result = <List<List<int>>>[], seen = <String>{};
  for (var r = 0; r < 4; r++) {
    final minX = cells.map((p) => p[0]).reduce(min),
        minY = cells.map((p) => p[1]).reduce(min);
    cells = cells.map((p) => [p[0] - minX, p[1] - minY]).toList()
      ..sort((a, b) => a[1] == b[1] ? a[0] - b[0] : a[1] - b[1]);
    if (seen.add(cells.toString())) result.add(cells);
    cells = cells.map((p) => [-p[1], p[0]]).toList();
  }
  return result;
}

class Placement {
  final int rotation, x, y, lines, holes, aggregateHeight, bumpiness, maxHeight;
  final List<List<int>> board;
  Placement(
    this.rotation,
    this.x,
    this.y,
    this.lines,
    this.holes,
    this.aggregateHeight,
    this.bumpiness,
    this.maxHeight,
    this.board,
  );
  String get id => 'r${rotation}x$x';
  double get value =>
      0.760666 * lines -
      0.510066 * aggregateHeight -
      0.35663 * holes -
      0.184483 * bumpiness;
  Map<String, dynamic> get features => {
    'rotation': rotation,
    'column': x,
    'cleared': lines,
    'holes': holes,
    'height_sum': aggregateHeight,
    'roughness': bumpiness,
    'max_height': maxHeight,
  };
}

class Tetris {
  final int seed;
  late final Random rng;
  List<List<int>> board = List.generate(height, (_) => List.filled(width, 0));
  final List<String> _bag = [];
  late String piece, next;
  int steps = 0, lines = 0, score = 0;
  Tetris(this.seed) {
    rng = Random(seed);
    piece = _draw();
    next = _draw();
  }
  String _draw() {
    if (_bag.isEmpty) {
      _bag.addAll(shapes.keys);
      _bag.shuffle(rng);
    }
    return _bag.removeLast();
  }

  bool fits(List<List<int>> cells, int x, int y) => cells.every(
    (p) =>
        p[0] + x >= 0 &&
        p[0] + x < width &&
        p[1] + y >= 0 &&
        p[1] + y < height &&
        board[p[1] + y][p[0] + x] == 0,
  );
  List<Placement> candidates() {
    final result = <Placement>[];
    final rs = rotations(piece);
    for (var r = 0; r < rs.length; r++) {
      final cells = rs[r], w = rs[r].map((p) => p[0]).reduce(max) + 1;
      for (var x = 0; x <= width - w; x++) {
        if (!fits(cells, x, 0)) continue;
        var y = 0;
        while (fits(cells, x, y + 1)) {
          y++;
        }
        var b = board.map((row) => List<int>.from(row)).toList();
        for (final p in cells) {
          b[y + p[1]][x + p[0]] = shapes.keys.toList().indexOf(piece) + 1;
        }
        final cleared = b.where((row) => row.every((v) => v != 0)).length;
        b = b.where((row) => row.any((v) => v == 0)).toList();
        b.insertAll(0, List.generate(cleared, (_) => List.filled(width, 0)));
        final heights = List.filled(width, 0);
        var holes = 0;
        for (var col = 0; col < width; col++) {
          bool filled = false;
          for (var row = 0; row < height; row++) {
            if (b[row][col] != 0) {
              if (!filled) heights[col] = height - row;
              filled = true;
            } else if (filled) {
              holes++;
            }
          }
        }
        var bump = 0;
        for (var i = 1; i < width; i++) {
          bump += (heights[i] - heights[i - 1]).abs();
        }
        result.add(
          Placement(
            r,
            x,
            y,
            cleared,
            holes,
            heights.reduce((a, b) => a + b),
            bump,
            heights.reduce(max),
            b,
          ),
        );
      }
    }
    return result;
  }

  void apply(String id) {
    final p = candidates().where((p) => p.id == id).firstOrNull;
    if (p == null) throw StateError('Illegal placement: $id');
    board = p.board;
    steps++;
    lines += p.lines;
    score += [0, 100, 300, 500, 800][p.lines];
    piece = next;
    next = _draw();
  }

  Map<String, dynamic> request(List<Placement> options) => {
    'model': 'jev-latest',
    'state': {
      'game': 'Tetris 10x20. Choose one legal hard-drop placement.',
      'piece': piece,
      'next_piece': next,
      'board': board
          .map((r) => r.map((v) => v == 0 ? '.' : '#').join())
          .toList(),
    },
    'questions': {
      'move': {
        'type': 'choice',
        'instructions':
            'You are a careful Tetris player. Every option describes the board AFTER placing the piece and clearing complete rows. Do NOT choose by rotation number, column, option order or label. Compare the numeric outcomes of ALL options. First minimize holes (empty cells trapped below blocks). Among options with the fewest holes, maximize cleared lines. Then minimize height_sum, then roughness, then max_height. Smaller holes, height_sum, roughness and max_height are better; larger cleared is better. Return the label of the best outcome.',
        'criteria': {for (final p in options) p.id: p.features},
      },
    },
  };
}

bool dominated(Placement p, List<Placement> all) => all.any(
  (a) =>
      a.lines >= p.lines &&
      a.holes <= p.holes &&
      a.aggregateHeight <= p.aggregateHeight &&
      a.bumpiness <= p.bumpiness &&
      a.maxHeight <= p.maxHeight &&
      (a.lines > p.lines ||
          a.holes < p.holes ||
          a.aggregateHeight < p.aggregateHeight ||
          a.bumpiness < p.bumpiness ||
          a.maxHeight < p.maxHeight),
);

/// Discrete gravity: every accepted input advances gravity by one row.
/// Rotation is clockwise at the normalized shape origin, without wall kicks.
class StepTetris extends Tetris {
  int x = 3, y = 0, rotation = 0, actions = 0;
  bool over = false;
  StepTetris(super.seed) {
    over = !fits(cells, x, y);
  }
  List<List<int>> get cells => rotations(piece)[rotation];

  (int, int, int)? target(String action) {
    if (over) return null;
    var nx = x, nr = rotation;
    switch (action) {
      case 'left':
        nx--;
      case 'right':
        nx++;
      case 'rotate':
        nr = (rotation + 1) % rotations(piece).length;
      case 'down':
      case 'hard_drop':
        break;
      default:
        return null;
    }
    return fits(rotations(piece)[nr], nx, y) ? (nx, y, nr) : null;
  }

  Map<String, dynamic> actionOptions() => {
    for (final action in ['left', 'right', 'rotate', 'down', 'hard_drop'])
      if (target(action) case final t?)
        action: {
          'column_after_input': t.$1,
          'rotation_after_input': t.$3,
          'row_after_step': action == 'hard_drop'
              ? ghost!.y
              : fits(rotations(piece)[t.$3], t.$1, y + 1)
              ? y + 1
              : y,
          'locks_piece':
              action == 'hard_drop' ||
              !fits(rotations(piece)[t.$3], t.$1, y + 1),
        },
  };

  bool act(String action) {
    final t = target(action);
    if (t == null) return false;
    x = t.$1;
    rotation = t.$3;
    actions++;
    if (action == 'hard_drop') {
      while (fits(cells, x, y + 1)) {
        y++;
      }
    }
    if (action != 'hard_drop' && fits(cells, x, y + 1)) {
      y++;
      return true;
    }
    for (final cell in cells) {
      board[y + cell[1]][x + cell[0]] = shapes.keys.toList().indexOf(piece) + 1;
    }
    final cleared = board.where((row) => row.every((v) => v != 0)).length;
    board = board.where((row) => row.any((v) => v == 0)).toList();
    board.insertAll(0, List.generate(cleared, (_) => List.filled(width, 0)));
    steps++;
    lines += cleared;
    score += [0, 100, 300, 500, 800][cleared];
    piece = next;
    next = _draw();
    x = 3;
    y = 0;
    rotation = 0;
    over = !fits(cells, x, y);
    return true;
  }

  List<List<int>> get displayBoard {
    final result = board.map((r) => List<int>.from(r)).toList();
    if (!over) {
      for (final c in cells) {
        result[y + c[1]][x + c[0]] = shapes.keys.toList().indexOf(piece) + 1;
      }
    }
    return result;
  }

  Placement? get ghost {
    if (over) return null;
    var row = y;
    while (fits(cells, x, row + 1)) {
      row++;
    }
    return Placement(rotation, x, row, 0, 0, 0, 0, 0, board);
  }

  Map<String, dynamic> actionRequest() => {
    'model': 'jev-latest',
    'state': {
      'worked_scoring_examples': scoringScenarios,
      'game':
          'Step Tetris 10x20. Each accepted action is followed by gravity of one row. If descent is blocked, lock and spawn next piece. No wall kicks or hold. hard_drop falls to the lowest reachable row and immediately locks.',
      'board': board
          .map((r) => r.map((v) => v == 0 ? '.' : '#').join())
          .toList(),
      'active': {
        'piece': piece,
        'column': x,
        'row': y,
        'rotation': rotation,
        'cells': cells,
      },
      'rotations': rotations(piece),
      'next_piece': next,
    },
    'questions': {
      'move': {
        'type': 'choice',
        'instructions':
            '''Play Tetris for the highest score by clearing full rows and avoiding game over. Ending early is failure. Movement and locking score zero.
Coordinates: board[row][column], both zero-based; top=0, bottom=19, left=0, right=9. # occupied, . empty. Active cells are separate from board. Each [dx,dy] means column=active.column+dx, row=active.row+dy. [[0,0],[0,1],[0,2],[0,3]] is VERTICAL.
One action first moves left/right or rotates clockwise at the same origin (no wall kicks), then attempts one row of gravity. down only attempts one row of gravity. hard_drop is a separate action: descend at the current column and rotation until blocked, then lock immediately. It does not move sideways or rotate; use those actions first. The turn stops after hard_drop, so never plan actions for the next piece in the same turn. Blocked gravity locks the piece; touching support does not lock until the next blocked descent. Full rows disappear and score 100/300/500/800. Next piece spawns at column3,row0; overlap ends game.
Legal first-step outcomes are already computed by the engine. locks_piece=true means lock immediately at row_after_step, NOT a recommendation. If locking near the spawn would end the game, choose a non-locking escape. To fill a gap, move toward its column before descending. Compare left AND right before choosing down; down does not reposition the piece. Plan only the current piece.
STRATEGY: Fill all 10 columns of a horizontal row to erase it and free space. First avoid immediate game over; then prefer a reachable plan that clears rows now, with more clears preferred. Do not sacrifice an available safe clear just to make a flatter surface or wait for a future multi-line clear. If no clear is possible now, fill gaps in nearly complete rows without sealing empty cells underneath. Preserve access to gaps. Compare height and flatness only after row completion and holes. Moving, rotating and falling are means to achieve a useful landing, not goals themselves.
$scoringExamples
Think in at most three brief sentences: identify target or danger, compare first-step outcomes, choose sequence. Once a safe useful action is found, stop rechecking and output the tool call.
Return only the option label corresponding to your chosen action, as requested by the surrounding choice interface.''',
        'criteria': actionOptions(),
      },
    },
  };
}

/// Executes a model's bounded plan; a plan never controls the next piece.
class TurnExecutor {
  final StepTetris game;
  final List<String> plan;
  final int initialPieces;
  int executed = 0;
  String? stopReason;
  TurnExecutor(this.game, List<String> actions)
    : plan = List.unmodifiable(actions),
      initialPieces = game.steps {
    if (plan.isEmpty ||
        plan.length > 8 ||
        plan.any(
          (a) => !['left', 'right', 'rotate', 'down', 'hard_drop'].contains(a),
        )) {
      throw ArgumentError('Expected 1..8 valid action names');
    }
  }
  bool advance() {
    if (stopReason != null) return false;
    if (game.over) {
      stopReason = 'game_over';
      return false;
    }
    if (game.steps != initialPieces) {
      stopReason = 'piece_locked';
      return false;
    }
    if (!game.act(plan[executed])) {
      stopReason = 'invalid_action';
      return false;
    }
    executed++;
    if (game.over) {
      stopReason = 'game_over';
    } else if (game.steps != initialPieces) {
      stopReason = 'piece_locked';
    } else if (executed == plan.length) {
      stopReason = 'plan_complete';
    }
    return true;
  }
}

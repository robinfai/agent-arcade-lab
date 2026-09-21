// Raw observations and action meanings only: no search, forecast, ranking,
// safety labels, legal-action filtering, demonstrations, or execution correction.
import 'game.dart';
import 'snake_game.dart';
import 'jev_client.dart';

Map<String, dynamic> rawTetrisRequest(StepTetris game) => {
  'model': 'jev-latest',
  'state': {
    'game': 'Tetris',
    'width': width,
    'height': height,
    'board': game.board
        .map((row) => row.map((v) => v == 0 ? '.' : '#').join())
        .toList(),
    'active': {
      'piece': game.piece,
      'column': game.x,
      'row': game.y,
      'rotation': game.rotation,
      'cells': game.cells,
    },
    'rotations': rotations(game.piece),
    'next_piece': game.next,
    'score': game.score,
    'lines': game.lines,
    'actions': game.actions,
  },
  'questions': {
    'move': {
      'type': 'choice',
      'instructions':
          'Play Tetris to maximize score and survive. Choose exactly one action. '
          'Coordinates are zero-based: x increases right, y increases down. '
          'The board contains locked blocks (#); active cells are [dx,dy] offsets '
          'from active.column,row and are separate from the board. '
          'Rotation advances to the next listed rotation at the same origin, with no wall kicks. '
          'A valid left/right/rotate input is followed by one row of gravity. '
          'down only applies one row of gravity. Blocked gravity locks the piece. '
          'hard_drop descends at the current column/rotation and locks immediately. '
          'A sideways/rotation collision rejects the input without gravity. '
          'Complete rows disappear; clearing 1/2/3/4 rows scores 100/300/500/800. '
          'The next piece spawns at column 3, row 0, rotation 0; overlap ends the game. '
          'There is no hold, timer gravity, or reward for moving/locking. '
          'No candidate outcomes or recommended actions are supplied.',
      'criteria': {
        'left': 'Move one column left, then apply gravity.',
        'right': 'Move one column right, then apply gravity.',
        'rotate': 'Advance to the next rotation, then apply gravity.',
        'down': 'Apply one row of gravity.',
        'hard_drop': 'Drop at current column and rotation, then lock.',
      },
    },
  },
};

Map<String, dynamic> rawSnakeRequest(SnakeArena game, int index) => {
  'model': 'jev-latest',
  'state': {
    'game': game.snakes.length == 1
        ? 'Single-player Snake'
        : 'Two-player Snake',
    'width': SnakeArena.size,
    'height': SnakeArena.size,
    'frame': game.frame,
    'you': index,
    'food': game.food == null ? null : [game.food!.$1, game.food!.$2],
    'snakes': [
      for (var i = 0; i < game.snakes.length; i++)
        {
          'index': i,
          'body_head_to_tail': [
            for (final cell in game.snakes[i].body) [cell.$1, cell.$2],
          ],
          'heading': ['up', 'right', 'down', 'left'][game.snakes[i].direction],
          'score': game.snakes[i].score,
        },
    ],
  },
  'questions': {
    'move': {
      'type': 'choice',
      'instructions':
          'Play Snake to maximize food score and survive. Choose one relative action. '
          'Coordinates [x,y] start at the top-left; x increases right, y increases down. '
          'Each snake turns relative to its heading, then moves one cell; all snakes move simultaneously. '
          'Eating food scores 10 and grows by one; otherwise the tail cell vacates. '
          'Hitting a wall or any non-vacating body cell kills the snake. '
          'Two heads entering the same cell or swapping head cells collide. '
          'The game ends on any snake collision, or when no space remains for food. '
          'Food respawns in an empty cell after eating. '
          'No safety evaluation, route, or recommended action is supplied.',
      'criteria': {
        'forward': 'Keep the current heading and move one cell.',
        'left': 'Turn 90 degrees left and move one cell.',
        'right': 'Turn 90 degrees right and move one cell.',
      },
    },
  },
};

Future<Map<String, dynamic>> decideRawTetris(
  JevClient api,
  StepTetris game,
) async {
  final request = rawTetrisRequest(game);
  final data = await api.decide(request);
  final choice = data['choice'];
  if (data['error'] != null ||
      !(request['questions']['move']['criteria'] as Map).containsKey(choice)) {
    throw StateError('Invalid JEV action: $choice');
  }
  return {
    ...data,
    'actions': [choice],
    'raw_choice': choice,
    'executed_choice': choice,
    'corrected': false,
    'correction_reason': 'JEV 无程序辅助',
  };
}

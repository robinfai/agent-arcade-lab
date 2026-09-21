/// Verified by scenario_examples_test.dart against the actual step engine.
/// Sparse boards keep demonstrations separate from the live board and compact.
const scoringScenarios = {
  'purpose':
      'Worked teaching examples only, NOT the live board. Do not copy actions blindly. In placement-choice mode select a CURRENT candidate with a useful outcome; do not output example names as placement IDs.',
  'coordinates':
      'Zero-based columns 0..9 and rows 0..19. board_rows lists locked cells only; unlisted rows are "..........". # occupied, . empty. Active cells are [dx,dy] offsets from column,row. Each left/right/rotate/down also applies one row of gravity. hard_drop locks immediately and ends this piece.',
  'examples': [
    {
      'name': 'fill_bottom_left',
      'board_rows': {'19': '....######'},
      'active': {
        'piece': 'I',
        'column': 3,
        'row': 0,
        'rotation': 0,
        'cells': [
          [0, 0],
          [1, 0],
          [2, 0],
          [3, 0],
        ],
      },
      'next_piece': 'O',
      'actions': ['left', 'left', 'left', 'hard_drop'],
      'target': {'column': 0, 'rotation': 0},
      'result': {'lines_cleared': 1, 'score_delta': 100, 'game_over': false},
      'why':
          'The horizontal I fills columns 0..3 of row 19; all ten cells are then full and the row disappears.',
    },
    {
      'name': 'fill_bottom_right',
      'board_rows': {'19': '######....'},
      'active': {
        'piece': 'I',
        'column': 3,
        'row': 0,
        'rotation': 0,
        'cells': [
          [0, 0],
          [1, 0],
          [2, 0],
          [3, 0],
        ],
      },
      'next_piece': 'O',
      'actions': ['right', 'right', 'right', 'hard_drop'],
      'target': {'column': 6, 'rotation': 0},
      'result': {'lines_cleared': 1, 'score_delta': 100, 'game_over': false},
      'why':
          'The horizontal I fills columns 6..9 of row 19. Dropping at the original column 3 would miss the gap.',
    },
    {
      'name': 'square_completes_two_rows',
      'board_rows': {'18': '####..####', '19': '####..####'},
      'active': {
        'piece': 'O',
        'column': 3,
        'row': 0,
        'rotation': 0,
        'cells': [
          [0, 0],
          [1, 0],
          [0, 1],
          [1, 1],
        ],
      },
      'next_piece': 'O',
      'actions': ['right', 'down', 'hard_drop'],
      'target': {'column': 4, 'rotation': 0},
      'result': {'lines_cleared': 2, 'score_delta': 300, 'game_over': false},
      'why':
          'Move to columns 4..5, then descend. The O fills both row gaps. down advances one row; hard_drop finishes the remaining descent.',
    },
    {
      'name': 'rotate_into_four_row_well',
      'board_rows': {
        '16': '##.#######',
        '17': '##.#######',
        '18': '##.#######',
        '19': '##.#######',
      },
      'active': {
        'piece': 'I',
        'column': 3,
        'row': 0,
        'rotation': 0,
        'cells': [
          [0, 0],
          [1, 0],
          [2, 0],
          [3, 0],
        ],
      },
      'next_piece': 'O',
      'actions': ['rotate', 'left', 'hard_drop'],
      'target': {'column': 2, 'rotation': 1},
      'result': {'lines_cleared': 4, 'score_delta': 800, 'game_over': false},
      'why':
          'Rotate I to vertical, align column 2, then drop. Its four cells fill rows 16..19. Without rotation it cannot fit this one-column well.',
    },
    {
      'name': 'rotate_and_move_right_for_three_rows',
      'board_rows': {
        '17': '#######.##',
        '18': '#######.##',
        '19': '#######.##',
      },
      'active': {
        'piece': 'I',
        'column': 3,
        'row': 0,
        'rotation': 0,
        'cells': [
          [0, 0],
          [1, 0],
          [2, 0],
          [3, 0],
        ],
      },
      'next_piece': 'O',
      'actions': ['rotate', 'right', 'right', 'right', 'right', 'hard_drop'],
      'target': {'column': 7, 'rotation': 1},
      'result': {'lines_cleared': 3, 'score_delta': 500, 'game_over': false},
      'why':
          'The vertical I fills the column-7 gaps of rows 17..19. Those three rows disappear; its fourth cell remains on the board. Locking does not end the game.',
    },
  ],
};

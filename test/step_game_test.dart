import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/game.dart';

void main() {
  test('midair inputs each advance one row, down does not hard drop', () {
    final g = StepTetris(0)..piece = 'T';
    expect(g.act('down'), true);
    expect((g.x, g.y, g.steps, g.actions), (3, 1, 0, 1));
    g.act('left');
    expect((g.x, g.y), (2, 2));
    g.act('rotate');
    expect((g.rotation, g.y, g.steps), (1, 3, 0));
    expect(g.board.expand((r) => r).where((v) => v != 0), isEmpty);
    expect(g.displayBoard.expand((r) => r).where((v) => v != 0).length, 4);
  });
  test('wall and stack reject inputs without time advancement; no kick', () {
    final g = StepTetris(0)
      ..piece = 'I'
      ..rotation = 1
      ..x = 9;
    expect(g.act('rotate'), false);
    expect(g.act('right'), false);
    expect((g.x, g.y, g.actions), (9, 0, 0));
    g.board[0][8] = 2;
    expect(g.act('left'), false);
    expect(g.actionOptions().keys, ['down', 'hard_drop']);
  });
  test('can slide under an overhang after descending', () {
    final g = StepTetris(0)
      ..piece = 'O'
      ..x = 3
      ..y = 5;
    g.board[4][2] = 1;
    expect(g.act('left'), true);
    expect((g.x, g.y), (2, 6));
    expect(g.steps, 0);
  });
  test('landing then next input locks, clears, and spawns at center', () {
    final g = StepTetris(0)
      ..piece = 'I'
      ..rotation = 1
      ..x = 4
      ..y = 15;
    for (var y = 16; y < 20; y++) {
      g.board[y] = List.generate(10, (x) => x == 4 ? 0 : 2);
    }
    final next = g.next;
    g.act('down');
    expect((g.y, g.steps), (16, 0));
    g.act('down');
    expect((g.steps, g.lines, g.score, g.actions), (1, 4, 800, 2));
    expect((g.piece, g.x, g.y, g.rotation), (next, 3, 0, 0));
  });
  test('spawn collision ends game and rejects subsequent actions', () {
    final g = StepTetris(0)
      ..piece = 'O'
      ..x = 0
      ..y = 18;
    g.board[0] = List.filled(10, 1)..[9] = 0;
    g.act('down');
    expect(g.over, true);
    expect(g.actionOptions(), isEmpty);
    expect(g.act('down'), false);
    expect(g.steps, 1);
  });
}

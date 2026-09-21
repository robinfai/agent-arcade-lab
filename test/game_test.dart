import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/main.dart';

void main() {
  test('unique tetromino rotations and cells', () {
    expect(
      [for (final p in shapes.keys) rotations(p).length],
      [2, 1, 4, 2, 2, 4, 4],
    );
    for (final p in shapes.keys) {
      for (final r in rotations(p)) {
        expect(r.length, 4);
        expect(r.map((p) => p.toString()).toSet().length, 4);
      }
    }
  });
  test('seven bag and seed reproducibility', () {
    final a = Tetris(42), b = Tetris(42);
    final pieces = <String>[];
    for (var i = 0; i < 7; i++) {
      pieces.add(a.piece);
      expect(a.piece, b.piece);
      final opts = a.candidates()..sort((a, b) => b.value.compareTo(a.value));
      a.apply(opts.first.id);
      b.apply(opts.first.id);
      expect(a.board, b.board);
    }
    expect(pieces.toSet().length, 7);
  });
  test('I clears four rows, preserves dimensions and score', () {
    final g = Tetris(0);
    g.piece = 'I';
    for (var y = 16; y < 20; y++) {
      g.board[y] = List.generate(10, (x) => x == 4 ? 0 : 2);
    }
    final p = g.candidates().singleWhere((p) => p.rotation == 1 && p.x == 4);
    expect(p.lines, 4);
    g.apply(p.id);
    expect(g.lines, 4);
    expect(g.score, 800);
    expect(g.board.length, 20);
    expect(g.board.expand((r) => r).every((v) => v == 0), true);
  });
  test('invalid action does not mutate; occupied ceiling is terminal', () {
    final g = Tetris(0);
    expect(() => g.apply('bad'), throwsStateError);
    expect(g.steps, 0);
    g.board = List.generate(20, (_) => List.filled(10, 1));
    expect(g.candidates(), isEmpty);
  });
  test(
    'all offered landings are collision-free and preserve cell accounting',
    () {
      final g = Tetris(2);
      for (var i = 0; i < 60; i++) {
        final options = g.candidates();
        if (options.isEmpty) break;
        final before = g.board.expand((r) => r).where((v) => v != 0).length;
        for (final p in options) {
          expect(
            p.board.expand((r) => r).where((v) => v != 0).length,
            before + 4 - p.lines * 10,
          );
          expect(g.fits(rotations(g.piece)[p.rotation], p.x, p.y), true);
          expect(g.fits(rotations(g.piece)[p.rotation], p.x, p.y + 1), false);
        }
        options.sort((a, b) => b.value.compareTo(a.value));
        g.apply(options.first.id);
      }
    },
  );
  testWidgets('renders game controls and supports manual placement', (
    tester,
  ) async {
    await tester.pumpWidget(const TetrisApp());
    expect(find.text('让小模型，下一步。'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('下落一步'));
    await tester.tap(find.byTooltip('下落一步'));
    await tester.pump();
    expect(find.textContaining('动作次数：1'), findsOneWidget);
    expect(find.textContaining('下落一格，受阻则锁定'), findsOneWidget);
  });
}

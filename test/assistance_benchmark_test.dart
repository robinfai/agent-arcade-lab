import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_cycle.dart';
import '../tool/benchmark_assistance.dart'
    show rawSnakeAbsolute, requestToolOutput;

void main() {
  test(
    'paired Snake arms have identical starts and fixed action vocabulary',
    () {
      final raw = SnakeArena(20260921, names: const ['model']);
      final assisted = SnakeArena(20260921, names: const ['model']);
      SnakeCycle(raw);
      final cycle = SnakeCycle(assisted);
      expect(raw.snakes.single.body, assisted.snakes.single.body);
      expect(raw.snakes.single.direction, assisted.snakes.single.direction);
      expect(raw.food, assisted.food);
      final request = rawSnakeAbsolute(raw);
      expect(
        request['questions']['move']['criteria'].keys,
        cycle.request()['questions']['move']['criteria'].keys,
      );
      expect(
        jsonEncode(request['questions']['move']['criteria']),
        isNot(contains('Safe')),
      );
      expect(
        jsonEncode(request['questions']['move']['criteria']),
        isNot(contains('Best')),
      );
    },
  );
  test(
    'tool-format correction changes no observation or candidate meaning',
    () {
      final game = SnakeArena(20260921, names: const ['model']);
      SnakeCycle(game);
      final request = rawSnakeAbsolute(game);
      final before = jsonDecode(jsonEncode(request));
      requestToolOutput(request);
      expect(request['state'], before['state']);
      expect(
        request['questions']['move']['criteria'],
        before['questions']['move']['criteria'],
      );
      expect(
        request['questions']['move']['instructions'],
        startsWith(before['questions']['move']['instructions']),
      );
      expect(
        request['questions']['move']['instructions'],
        contains('Output only the tool call'),
      );
    },
  );
}

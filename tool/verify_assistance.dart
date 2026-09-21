import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_cycle.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/tetris_assist.dart';
import 'package:agent_arcade_lab/unassisted.dart';
import 'benchmark_assistance.dart' show rawSnakeAbsolute, requestToolOutput;

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Provide matrix root');
  var runs = 0, totalSteps = 0;
  for (final file
      in Directory(args.single)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('/summary.json'))) {
    final summary = jsonDecode(file.readAsStringSync());
    if (summary['max_steps'] is! int ||
        summary['max_steps'] < 1 ||
        summary['requests'] > summary['max_requests']) {
      throw StateError('Invalid budget: ${file.path}');
    }
    final tetris = StepTetris(summary['seed']);
    final snake = SnakeArena(summary['seed'], names: const ['model']);
    final cycle = SnakeCycle(snake);
    final isTetris = summary['game'] == 'tetris', mode = summary['mode'];
    var count = 0, corrections = 0, invalid = 0;
    int steps() => isTetris ? tetris.actions : snake.frame;
    bool over() => isTetris ? tetris.over : snake.over;
    Map<String, dynamic> snapshot() => isTetris
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
            'score': tetris.score,
            'over': tetris.over,
          }
        : {
            'body': [
              for (final p in snake.snakes.single.body) [p.$1, p.$2],
            ],
            'heading': snake.snakes.single.direction,
            'food': snake.food == null
                ? null
                : [snake.food!.$1, snake.food!.$2],
            'frame': snake.frame,
            'score': snake.snakes.single.score,
            'alive': snake.snakes.single.alive,
            'over': snake.over,
          };
    void same(dynamic a, dynamic b, String what) {
      if (jsonEncode(a) != jsonEncode(b)) {
        throw StateError('${file.path}: $what at record $count');
      }
    }

    final dir = file.parent.path;
    same(
      jsonDecode(File('$dir/initial.json').readAsStringSync()),
      snapshot(),
      'initial',
    );
    for (final line in File('$dir/trace.jsonl').readAsLinesSync()) {
      final row = jsonDecode(line);
      count++;
      same(row['before'], snapshot(), 'before');
      same(row['proposed'], row['response']['choice'], 'original choice');
      final proposed = row['proposed'];
      late Map<String, dynamic> request;
      List<String> planned = [];
      var changed = false;
      if (isTetris) {
        if (mode == 'raw') {
          request = rawTetrisRequest(tetris);
          if (proposed != null) planned = [proposed];
        } else {
          final plans = reachablePlans(tetris);
          request = uniformTetrisRequest(plans);
          if (row['response']['error'] == null && proposed != null) {
            final result = correctPlacement(
              plans,
              Map<String, dynamic>.from(row['response']),
              enabled: true,
            );
            changed = result['corrected'] == true;
            final full = plans
                .singleWhere((p) => p.id == result['choice'])
                .actions;
            same(row['full_plan'], full, 'full plan');
            planned = full
                .take((summary['max_steps'] as int) - steps())
                .toList();
          }
        }
      } else {
        request = mode == 'raw' ? rawSnakeAbsolute(snake) : cycle.request();
        if (row['response']['error'] == null &&
            proposed != null &&
            SnakeCycle.actions.contains(proposed)) {
          final executed = mode == 'raw'
              ? proposed
              : cycle.executeChoice(
                  proposed,
                  row['response']['probabilities'] == null
                      ? null
                      : Map<String, dynamic>.from(
                          row['response']['probabilities'],
                        ),
                );
          changed = executed != proposed;
          planned = [executed];
        }
      }
      if (summary['explicit_tool_instruction'] == true) {
        requestToolOutput(
          request,
          summary['tool_output_name'] ?? 'place_piece',
        );
      }
      if (summary['tool_choice'] == 'required') {
        request['tool_choice'] = 'required';
        same(row['response']['tool_choice'], 'required', 'tool choice');
        same(
          row['response']['constrained_decoding'],
          true,
          'format constraint',
        );
      }
      same(row['request'], request, 'request');
      same(row['corrected'], changed, 'correction');
      if (changed) corrections++;
      final actual = <String>[];
      final valid =
          row['response']['error'] == null &&
          proposed != null &&
          (request['questions']['move']['criteria'] as Map).containsKey(
            proposed,
          ) &&
          planned.isNotEmpty;
      var accepted = valid;
      if (valid) {
        for (final action in planned) {
          if (over() || steps() >= summary['max_steps']) break;
          if (isTetris) {
            if (!tetris.act(action)) {
              invalid++;
              accepted = false;
              break;
            }
          } else {
            snake.advance([action]);
          }
          actual.add(action);
        }
      }
      same(row['accepted'], accepted, 'accepted');
      same(row['executed_actions'], actual, 'actions');
      same(row['after'], snapshot(), 'after');
      if (steps() > summary['max_steps']) throw StateError('Cap exceeded');
    }
    same(summary['final_state'], snapshot(), 'final state');
    same(summary['steps'], steps(), 'steps');
    same(summary['score'], snapshot()['score'], 'score');
    same(summary['over'], over(), 'over');
    same(summary['corrections'], corrections, 'correction count');
    same(summary['invalid_actions'], invalid, 'invalid count');
    if (summary['end_reason'] == 'step_cap') {
      same(steps(), summary['max_steps'], 'exact cap');
    }
    if (mode == 'program') {
      same(summary['requests'], 0, 'no inference');
    } else if (summary['end_reason'] != 'request_error') {
      same(summary['requests'], count, 'requests');
    }
    stdout.writeln(
      '${summary['label']}/${summary['game']}/$mode: ${steps()} steps verified, score=${summary['score']}, ${summary['end_reason']}',
    );
    runs++;
    totalSteps += steps();
  }
  stdout.writeln(
    'Verified $runs runs, $totalSteps actual actions; all within their recorded caps.',
  );
}

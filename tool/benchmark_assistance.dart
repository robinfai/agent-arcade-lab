// Paired, bounded trials. This tool does not change any page defaults.
import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/snake_cycle.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';
import 'package:agent_arcade_lab/tetris_assist.dart';
import 'package:agent_arcade_lab/unassisted.dart';
import 'package:agent_arcade_lab/jev_client.dart';

Map<String, dynamic> rawSnakeAbsolute(SnakeArena game) {
  final request = rawSnakeRequest(game, 0);
  request['questions']['move']['instructions'] =
      'Play single-player Snake for food score and survival. Choose one absolute direction. '
      'Coordinates [x,y] start at top-left, x increases right and y down. '
      'The body is ordered head to tail. Each action moves one cell. '
      'Food scores 10 and grows the body by one; otherwise the tail vacates. '
      'Walls and non-vacating body cells kill the snake, including reversing into the neck. '
      'The game ends on collision or when the board is full. Food respawns in an empty cell. '
      'Choose using only the supplied current state; no route or outcome is supplied.';
  request['questions']['move']['criteria'] = {
    'UP': 'Move one cell up (y minus 1).',
    'DOWN': 'Move one cell down (y plus 1).',
    'LEFT': 'Move one cell left (x minus 1).',
    'RIGHT': 'Move one cell right (x plus 1).',
  };
  return request;
}

void requestToolOutput(
  Map<String, dynamic> req, [
  String toolName = 'place_piece',
]) {
  req['questions']['move']['instructions'] +=
      ' Call $toolName exactly once with placement_id set to one of the provided option labels. Output only the tool call, no explanation.';
}

Future<void> main(List<String> args) async {
  if (args.length < 5 ||
      args
          .skip(5)
          .any(
            (a) =>
                !['explicit-tool', 'required-tool'].contains(a) &&
                !RegExp(r'^(seed|max-steps|max-seconds)=\d+$').hasMatch(a),
          )) {
    throw ArgumentError(
      'MODEL GAME(raw tetris|snake) MODE(raw|assisted|program) URL OUTPUT',
    );
  }
  final explicitTool = args.skip(5).contains('explicit-tool');
  final requiredTool = args.skip(5).contains('required-tool');
  if (requiredTool && !['qwen08', 'qwen4'].contains(args[0])) {
    throw ArgumentError('required-tool is supported only by the Qwen backend');
  }
  final label = args[0],
      kind = args[1],
      mode = args[2],
      dir = Directory(args[4]);
  if (!['tetris', 'snake'].contains(kind) ||
      !['raw', 'assisted', 'program'].contains(mode)) {
    throw ArgumentError('Invalid game/mode');
  }
  int option(String name, int fallback) {
    final values = args.skip(5).where((a) => a.startsWith('$name='));
    if (values.length > 1) throw ArgumentError('Duplicate $name');
    return values.isEmpty ? fallback : int.parse(values.single.split('=').last);
  }

  final seed = option('seed', 20260921);
  final cap = option('max-steps', 2000);
  final maxSeconds = option('max-seconds', 3600);
  if (cap < 1 || maxSeconds < 1) {
    throw ArgumentError('Budgets must be positive');
  }
  if (dir.existsSync()) throw StateError('Refusing to overwrite ${dir.path}');
  dir.createSync(recursive: true);
  final endpoint = label == 'laya'
      ? '/v1/tool-decision?native=true'
      : label == 'qwen08' && kind == 'snake'
      ? '/v1/snake-decision'
      : '/v1/tool-decision';
  final toolName = endpoint == '/v1/snake-decision'
      ? 'snake_move'
      : 'place_piece';
  final api = JevClient(args[3], endpoint: endpoint);
  final tetris = StepTetris(seed),
      snake = SnakeArena(seed, names: const ['model']);
  // All arms share exactly this same initial body, heading, food and PRNG state.
  final cycle = SnakeCycle(snake);
  final stream = File('${dir.path}/trace.jsonl').openWrite();
  final timer = Stopwatch()..start();
  final started = DateTime.now().toUtc().toIso8601String();
  var requests = 0,
      corrections = 0,
      invalid = 0,
      inputTokens = 0,
      outputTokens = 0;
  var comparisons = 0, preferred = 0;
  var reason = 'step_cap';
  String? error, actualModel;
  final latencies = <double>[];
  int steps() => kind == 'tetris' ? tetris.actions : snake.frame;
  bool over() => kind == 'tetris' ? tetris.over : snake.over;
  Map<String, dynamic> state() => kind == 'tetris'
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
          'food': snake.food == null ? null : [snake.food!.$1, snake.food!.$2],
          'frame': snake.frame,
          'score': snake.snakes.single.score,
          'alive': snake.snakes.single.alive,
          'over': snake.over,
        };
  File('${dir.path}/initial.json').writeAsStringSync(jsonEncode(state()));
  Future<Map<String, dynamic>> infer(Map<String, dynamic> req) async {
    requests++;
    if (requiredTool) req['tool_choice'] = 'required';
    if (explicitTool && label.startsWith('qwen')) {
      requestToolOutput(req, toolName);
    }
    final data = await api.decide(req);
    actualModel = data['model'] as String?;
    if (actualModel == null ||
        (label == 'qwen4' && !actualModel!.contains('3.5-4B')) ||
        (label == 'qwen08' && !actualModel!.contains('3.5-0.8B'))) {
      throw StateError('Unexpected model identity: $actualModel');
    }
    latencies.add((data['_http_ms'] as num).toDouble());
    inputTokens += (data['usage']?['input_tokens'] as num? ?? 0).toInt();
    outputTokens += (data['usage']?['output_tokens'] as num? ?? 0).toInt();
    return data;
  }

  try {
    while (!over() && steps() < cap && requests < cap) {
      if (timer.elapsed.inSeconds >= maxSeconds) {
        reason = 'time_cap';
        break;
      }
      final before = jsonDecode(jsonEncode(state()));
      late Map<String, dynamic> request;
      Map<String, dynamic> response = {};
      List<String> actions = [];
      String? proposed, executed;
      var corrected = false;
      List<String>? fullPlan;
      Map<String, dynamic>? correction;
      if (kind == 'tetris') {
        if (mode == 'raw') {
          request = rawTetrisRequest(tetris);
          response = await infer(request);
          proposed = response['choice'] as String?;
          executed = proposed;
          if (proposed != null) actions = [proposed];
        } else {
          final plans = reachablePlans(tetris);
          request = uniformTetrisRequest(plans);
          if (mode == 'program') {
            proposed = bestPlacement(plans).id;
            response = {'choice': proposed, 'model': 'program-only'};
          } else {
            response = await infer(request);
            proposed = response['choice'] as String?;
          }
          if (response['error'] == null && proposed != null) {
            correction = correctPlacement(plans, response, enabled: true);
            executed = correction['choice'];
            corrected = correction['corrected'] == true;
            if (corrected) corrections++;
            comparisons++;
            if (!corrected) preferred++;
            fullPlan = plans.singleWhere((p) => p.id == executed).actions;
            actions = fullPlan.take(cap - steps()).toList();
          }
        }
      } else {
        request = mode == 'raw' ? rawSnakeAbsolute(snake) : cycle.request();
        if (mode == 'program') {
          final safe = cycle.moves().where((m) => m.safe).toList();
          proposed = safe
              .reduce((a, b) => a.advance >= b.advance ? a : b)
              .action;
          response = {'choice': proposed, 'model': 'program-only'};
        } else {
          response = await infer(request);
          proposed = response['choice'] as String?;
        }
        if (response['error'] == null &&
            proposed != null &&
            SnakeCycle.actions.contains(proposed)) {
          executed = mode == 'raw'
              ? proposed
              : cycle.executeChoice(
                  proposed,
                  response['probabilities'] == null
                      ? null
                      : Map<String, dynamic>.from(response['probabilities']),
                );
          corrected = proposed != executed;
          if (corrected) corrections++;
          if (mode != 'raw') {
            comparisons++;
            final options = request['questions']['move']['criteria'] as Map;
            if ((options[proposed] as String).contains('Best')) preferred++;
          }
          actions = [executed];
        }
      }
      final candidates = request['questions']['move']['criteria'] as Map;
      final executedActions = <String>[];
      var accepted = true;
      if (response['error'] != null ||
          proposed == null ||
          !candidates.containsKey(proposed) ||
          actions.isEmpty) {
        reason = 'invalid_response';
        accepted = false;
        error = '${response['error'] ?? 'missing or unknown choice'}';
      } else {
        for (final action in actions) {
          if (steps() >= cap || over()) break;
          if (kind == 'tetris') {
            if (!tetris.act(action)) {
              invalid++;
              accepted = false;
              reason = 'invalid_action';
              break;
            }
          } else {
            snake.advance([action]);
          }
          executedActions.add(action);
        }
      }
      stream.writeln(
        jsonEncode({
          'index': requests,
          'request': request,
          'response': response,
          'proposed': proposed,
          'executed': executed,
          'corrected': corrected,
          'correction': correction,
          'full_plan': fullPlan,
          'executed_actions': executedActions,
          'accepted': accepted,
          'before': before,
          'after': state(),
        }),
      );
      await stream.flush();
      if (steps() % 50 == 0 || over() || !accepted || steps() == cap) {
        stdout.writeln(
          jsonEncode({
            'label': label,
            'game': kind,
            'mode': mode,
            'steps': steps(),
            'score': state()['score'],
            'requests': requests,
            'corrections': corrections,
            'over': over(),
            'reason': reason,
          }),
        );
      }
      if (!accepted) break;
    }
    if (over()) {
      reason = kind == 'tetris'
          ? 'spawn_blocked'
          : snake.food == null
          ? 'board_full'
          : 'collision';
    }
  } catch (e) {
    reason = 'request_error';
    error = e.toString();
  } finally {
    timer.stop();
    api.close();
    await stream.close();
    final summary = {
      'label': label,
      'game': kind,
      'mode': mode,
      'seed': seed,
      'max_steps': cap,
      'max_requests': cap,
      'max_seconds': maxSeconds,
      'explicit_tool_instruction': explicitTool,
      'tool_choice': requiredTool ? 'required' : 'auto',
      'tool_output_name': toolName,
      'endpoint': endpoint,
      'started_at': started,
      'model': actualModel ?? (mode == 'program' ? 'program-only' : null),
      'steps': steps(),
      'score': state()['score'],
      'over': over(),
      'end_reason': reason,
      'error': error,
      'requests': requests,
      'corrections': corrections,
      'candidate_comparisons': comparisons,
      'preferred_proposals': preferred,
      'invalid_actions': invalid,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'mean_http_ms': latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a + b) / latencies.length,
      'elapsed_seconds': timer.elapsedMilliseconds / 1000,
      'final_state': state(),
    };
    File(
      '${dir.path}/summary.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    stdout.writeln(jsonEncode(Map.of(summary)..remove('final_state')));
  }
}

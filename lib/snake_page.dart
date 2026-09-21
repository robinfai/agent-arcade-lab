import 'package:flutter/material.dart';
import 'snake_game.dart';
import 'snake_cycle.dart';
import 'snake_arena_assist.dart';
import 'jev_client.dart';

class SnakePage extends StatefulWidget {
  const SnakePage({super.key});
  @override
  State<SnakePage> createState() => _SnakePageState();
}

class _SnakePageState extends State<SnakePage> {
  final clients = [
    JevClient(
      const String.fromEnvironment(
        'LAYA_URL',
        defaultValue: 'http://127.0.0.1:8769',
      ),
      endpoint: '/v1/snake-decision',
    ),
    JevClient(
      const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://127.0.0.1:8765',
      ),
      endpoint: '/v1/snake-decision',
    ),
    JevClient(
      const String.fromEnvironment(
        'JEV_URL',
        defaultValue: 'http://127.0.0.1:8770',
      ),
      endpoint: '/v1/snake-decision',
    ),
  ];
  static const modelNames = ['Laya Multilingual 322M', 'Qwen 0.8B', 'JEV · 云端'];
  final arenaModels = [0, 1];
  bool solo = false;
  int soloModel = 0;
  bool shield = true;
  bool arenaShield = true;
  late ArenaAssist arenaAssist = ArenaAssist(game);
  SnakeCycle? cycle;
  int interventions = 0;
  String proposed = '—';
  List<int> get players => solo ? [soloModel] : arenaModels;
  SnakeArena game = SnakeArena(20260921, names: modelNames.take(2).toList());
  void configure({bool? single, int? model}) {
    solo = single ?? solo;
    soloModel = model ?? soloModel;
    reset(false);
  }

  bool running = false, busy = false;
  int epoch = 0, loop = 0;
  String status = '等待开始 · 双方共用同一帧，返回后统一结算';
  List<String> choices = ['—', '—'];
  List<double?> latencies = [null, null];
  @override
  void dispose() {
    epoch++;
    loop++;
    running = false;
    for (final c in clients) {
      c.close();
    }
    super.dispose();
  }

  Future<void> step() async {
    if (busy || game.over) {
      return;
    }
    final token = epoch;
    final active = players;
    final requests = [
      for (var i = 0; i < active.length; i++)
        solo
            ? cycle!.request(diagnostics: soloModel != 1)
            : arenaAssist.request(i),
    ];
    setState(() {
      busy = true;
      status = '模型决策中 · 棋盘保持第 ${game.frame} 帧';
    });
    try {
      final results = await Future.wait([
        for (var i = 0; i < active.length; i++)
          clients[active[i]].decide(requests[i]),
      ]);
      if (!mounted || token != epoch) {
        return;
      }
      for (var i = 0; i < results.length; i++) {
        if (results[i]['error'] != null ||
            !(solo ? SnakeCycle.actions : ['forward', 'left', 'right'])
                .contains(results[i]['choice'])) {
          throw StateError(
            '${modelNames[active[i]]} 未返回有效动作：${results[i]['error']}',
          );
        }
      }
      setState(() {
        choices = results.map((r) => r['choice'] as String).toList();
        latencies = results
            .map((r) => (r['_http_ms'] as num).toDouble())
            .toList();
        if (solo) {
          proposed = choices.single;
          if (shield) {
            choices = [
              cycle!.executeChoice(
                proposed,
                results.single['probabilities'] == null
                    ? null
                    : Map<String, dynamic>.from(
                        results.single['probabilities'],
                      ),
              ),
            ];
            if (choices.single != proposed) {
              interventions++;
            }
          }
        }
        if (!solo) {
          choices = arenaAssist.execute(choices, enabled: arenaShield);
        }
        game.advance(choices);
        status = game.over ? game.result : '第 ${game.frame} 帧已同时结算';
      });
    } catch (e) {
      if (mounted && token == epoch) {
        setState(() {
          running = false;
          status = '本帧未执行，已暂停：$e';
        });
      }
    } finally {
      if (mounted && token == epoch) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> toggle() async {
    if (running) {
      setState(() {
        running = false;
        loop++;
      });
      return;
    }
    final currentLoop = ++loop;
    setState(() => running = true);
    while (mounted && running && currentLoop == loop && !game.over) {
      await step();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (mounted && currentLoop == loop) {
      setState(() => running = false);
    }
  }

  void reset(bool randomSeed) => setState(() {
    epoch++;
    loop++;
    running = false;
    busy = false;
    game = SnakeArena(
      randomSeed ? DateTime.now().millisecondsSinceEpoch : game.seed,
      names: players.map((i) => modelNames[i]).toList(),
    );
    cycle = solo ? SnakeCycle(game) : null;
    arenaAssist = ArenaAssist(game);
    interventions = 0;
    proposed = '—';
    choices = List.filled(players.length, '—');
    latencies = List.filled(players.length, null);
    status = '新一局 · 种子 ${game.seed}';
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              solo ? '贪吃蛇 · 单模型独玩' : '贪吃蛇 · 同帧竞技',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('单模型独玩')),
                ButtonSegment(value: false, label: Text('多模型竞技')),
              ],
              selected: {solo},
              onSelectionChanged: busy || running
                  ? null
                  : (v) => configure(single: v.single),
            ),
            const SizedBox(height: 12),
            if (solo)
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: soloModel,
                decoration: const InputDecoration(labelText: '选择模型'),
                items: [
                  for (var i = 0; i < modelNames.length; i++)
                    DropdownMenuItem(value: i, child: Text(modelNames[i])),
                ],
                onChanged: busy || running
                    ? null
                    : (v) {
                        if (v != null) {
                          configure(model: v);
                        }
                      },
              )
            else
              Row(
                children: [
                  for (var slot = 0; slot < 2; slot++)
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: arenaModels[slot],
                        decoration: InputDecoration(
                          labelText: slot == 0 ? '青方模型' : '黄方模型',
                        ),
                        items: [
                          for (var i = 0; i < modelNames.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(modelNames[i]),
                            ),
                        ],
                        onChanged: busy || running
                            ? null
                            : (v) {
                                if (v != null) {
                                  arenaModels[slot] = v;
                                  reset(false);
                                }
                              },
                      ),
                    ),
                ],
              ),
            const Text('JEV 将游戏局面发送至云端；密钥由本地代理读取。'),
            if (solo)
              SwitchListTile(
                title: const Text('社区循环安全层'),
                subtitle: const Text('关闭后执行模型原始选择；切换会重开'),
                value: shield,
                onChanged: busy || running
                    ? null
                    : (v) {
                        shield = v;
                        reset(false);
                      },
              ),
            if (solo)
              Text(
                '模型原始选择：$proposed · 实际动作：${choices.first} · 纠错次数：$interventions',
              ),
            if (solo)
              Text(
                soloModel != 1
                    ? '纠错按模型概率选择安全方向；每步推理，未使用预录动作。'
                    : 'Qwen 无候选概率；纠错时由程序选择安全方向中的最大路线进展。',
              ),
            if (!solo)
              SwitchListTile(
                title: const Text('双方统一防循环辅助'),
                subtitle: const Text('同样的避险、重复局面检测和路径搜索；切换重开'),
                value: arenaShield,
                onChanged: busy || running
                    ? null
                    : (v) {
                        arenaShield = v;
                        reset(false);
                      },
              ),
            if (!solo) ...[
              for (var i = 0; i < 2; i++)
                Text(
                  '${game.names[i]} 原始：${arenaAssist.raw[i]} → 执行：${choices[i]} · 纠错 ${arenaAssist.corrections[i]} 次 · ${arenaAssist.reasons[i]}',
                ),
            ],
            const Text('切换玩法或模型会重新开局；运行中请先暂停。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: [
                for (var i = 0; i < game.snakes.length; i++)
                  Text(
                    '${i == 0 ? '青色' : '黄色'} ${game.names[i]}\n${game.snakes[i].score} 分 · 长度 ${game.snakes[i].body.length}\n${choices[i]} · ${latencies[i] == null ? '—' : '${latencies[i]!.round()} ms'}',
                    style: TextStyle(
                      color: i == 0
                          ? const Color(0xff58dcff)
                          : const Color(0xffffd26a),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('帧数：${game.frame} · 种子：${game.seed}'),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Semantics(
                    label: '贪吃蛇棋盘，${game.snakes.length} 条蛇，食物 ${game.food}',
                    child: CustomPaint(painter: _ArenaPainter(game)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: game.over || (busy && !running) ? null : toggle,
                  child: Text(
                    running
                        ? '暂停'
                        : solo
                        ? '开始独玩'
                        : '开始竞技',
                  ),
                ),
                OutlinedButton(
                  onPressed: busy || running || game.over ? null : step,
                  child: Text(solo ? '走一帧' : '双方走一帧'),
                ),
                OutlinedButton(
                  onPressed: () => reset(true),
                  child: const Text('随机新一局'),
                ),
                OutlinedButton(
                  onPressed: () => reset(false),
                  child: const Text('同种子重开'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(status),
            const SizedBox(height: 16),
            const Text(
              '独玩使用上/下/左/右绝对方向及社区循环路线；竞技使用前进/左转/右转，等全部响应后同时移动。食物被吃后随机刷新，吃一次加 10 分并增长。',
            ),
            const SizedBox(height: 8),
            const Text(
              '失败规则：头撞墙或任意蛇身即失败；两头同格或交换位置均判双方失败。未吃食物的尾格在本帧腾空，可进入。一方失败即结束该局。',
            ),
            const SizedBox(height: 8),
            const Text(
              '参考社区简短提示：程序为参赛模型标注当前帧安全性和最接近食物的选项。竞技使用双方一致的防循环辅助，不使用单蛇循环安全保证；路径基于当前身体，无法保证未来不碰撞。实际改写以上方开关及计数为准。请求失败时整帧暂停。暂停会完成正在请求的一帧。',
            ),
          ],
        ),
      ),
    ),
  );
}

class _ArenaPainter extends CustomPainter {
  final SnakeArena game;
  _ArenaPainter(this.game);
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / SnakeArena.size;
    final paint = Paint();
    for (var y = 0; y < SnakeArena.size; y++) {
      for (var x = 0; x < SnakeArena.size; x++) {
        paint.color = const Color(0xff18253a);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x * cell + 1, y * cell + 1, cell - 2, cell - 2),
            const Radius.circular(4),
          ),
          paint,
        );
      }
    }
    for (var i = 0; i < game.snakes.length; i++) {
      final snake = game.snakes[i];
      for (final p in snake.body) {
        paint.color = !snake.alive
            ? Colors.grey
            : i == 0
            ? const Color(0xff58dcff)
            : const Color(0xffffd26a);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(p.$1 * cell + 2, p.$2 * cell + 2, cell - 4, cell - 4),
            const Radius.circular(6),
          ),
          paint,
        );
      }
      final h = snake.body.first, d = SnakeArena.directions[snake.direction];
      paint.color = const Color(0xff0b1220);
      canvas.drawCircle(
        Offset(
          (h.$1 + .5 + d.$1 * .22) * cell,
          (h.$2 + .5 + d.$2 * .22) * cell,
        ),
        cell * .12,
        paint,
      );
    }
    if (game.food != null) {
      paint.color = const Color(0xffff738b);
      canvas.drawCircle(
        Offset((game.food!.$1 + .5) * cell, (game.food!.$2 + .5) * cell),
        cell * .3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArenaPainter oldDelegate) => true;
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'game.dart';
import 'jev_client.dart';
import 'assisted_player.dart';
import 'assisted_planner.dart';
import 'snake_page.dart';
import 'tetris_assist.dart';
import 'unassisted.dart';

void main() => runApp(const TetrisApp());
const colors = [
  Color(0xff18253a),
  Color(0xff58dcff),
  Color(0xffffd26a),
  Color(0xffb297ff),
  Color(0xff71e4ac),
  Color(0xffff738b),
  Color(0xff689bff),
  Color(0xffffad71),
];

class TetrisApp extends StatelessWidget {
  const TetrisApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Agent Arcade Lab',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff0b1220),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff71e4ac),
        brightness: Brightness.dark,
      ),
    ),
    home: const GameLab(),
  );
}

class GameLab extends StatefulWidget {
  const GameLab({super.key});
  @override
  State<GameLab> createState() => _GameLabState();
}

class _GameLabState extends State<GameLab> {
  bool snake = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('俄罗斯方块'),
                      icon: Icon(Icons.grid_view),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('贪吃蛇'),
                      icon: Icon(Icons.route),
                    ),
                  ],
                  selected: {snake},
                  onSelectionChanged: (v) => setState(() => snake = v.single),
                ),
                const Text('切换游戏会停止 AI 并重新开局'),
              ],
            ),
          ),
          Expanded(child: snake ? const SnakePage() : const GamePage()),
        ],
      ),
    ),
  );
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const localUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8765',
  );
  static const deepseekUrl = String.fromEnvironment(
    'DEEPSEEK_URL',
    defaultValue: 'http://127.0.0.1:8767',
  );
  static const kevUrl = String.fromEnvironment(
    'KEV_URL',
    defaultValue: 'http://127.0.0.1:8768',
  );
  static const layaUrl = String.fromEnvironment(
    'LAYA_URL',
    defaultValue: 'http://127.0.0.1:8769',
  );
  static const jevUrl = String.fromEnvironment(
    'JEV_URL',
    defaultValue: 'http://127.0.0.1:8770',
  );
  String selectedModel = 'laya';
  var api = JevClient(layaUrl, endpoint: '/v1/tool-decision');
  bool tetrisShield = true;
  int tetrisCorrections = 0;
  String tetrisDecision = '尚无模型选择';
  late var assistedPlayer = AssistedPlayer(
    api,
    uniformAssistance: true,
    correctChoices: tetrisShield,
  );
  void recordCorrection(Map<String, dynamic> data) {
    if (data['continued_plan'] == true) {
      return;
    }
    if (data['corrected'] == true) {
      tetrisCorrections++;
    }
    tetrisDecision =
        "原始：${data['raw_choice']} → 执行：${data['executed_choice']} · ${data['correction_reason']}";
  }

  StepTetris game = StepTetris(20260920);
  bool running = false, busy = false;
  int epoch = 0, loopEpoch = 0, turns = 0;
  double? latency, confidence;
  String modelName = '未连接模型';
  String status = '等待开始 · 模型在本机运行', lastChoice = '—';
  List<dynamic> history = [], games = [];
  List<List<int>>? replayBoard;
  Timer? replayTimer;
  int replayIndex = 0, replayGame = 0;
  @override
  void initState() {
    super.initState();
    loadReport();
    loadModel();
  }

  Future<void> loadModel() async {
    try {
      final response = await http
          .get(Uri.parse('${api.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(response.body);
      if (mounted && response.statusCode == 200 && data['ready'] == true) {
        setState(() {
          modelName = data['model'] as String;
          selectedModel = modelName.startsWith('jev-')
              ? 'jev'
              : modelName.contains('laya-')
              ? 'laya'
              : modelName.contains('kev-4b')
              ? 'kev4'
              : modelName.contains('deepseek')
              ? 'deepseek'
              : modelName.contains('4B')
              ? 'qwen4'
              : 'qwen08';
        });
      }
    } catch (_) {
      /* Keep connection status visible. */
    }
  }

  Future<void> selectModel(String? selection) async {
    if (selection == null || busy || running) return;
    epoch++;
    loopEpoch++;
    assistedPlayer.reset();
    setState(() {
      busy = true;
      status = '正在切换模型…';
    });
    try {
      final remote =
          selection == 'jev' ||
          selection == 'deepseek' ||
          selection == 'kev4' ||
          selection == 'laya';
      final base = selection == 'jev'
          ? jevUrl
          : selection == 'laya'
          ? layaUrl
          : selection == 'kev4'
          ? kevUrl
          : remote
          ? deepseekUrl
          : localUrl;
      final expected = selection == 'qwen4'
          ? 'mlx-community/Qwen3.5-4B-4bit'
          : 'mlx-community/Qwen3.5-0.8B-4bit';
      final response = remote
          ? await http
                .get(Uri.parse('$base/health'))
                .timeout(const Duration(seconds: 10))
          : await http
                .post(
                  Uri.parse('$base/v1/load-model'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'model': expected}),
                )
                .timeout(const Duration(seconds: 180));
      if (response.statusCode != 200) {
        throw StateError('服务返回 ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data['ready'] != true ||
          (remote
              ? data['model'] !=
                    (selection == 'jev'
                        ? 'jev-latest'
                        : selection == 'laya'
                        ? 'aac6fef/laya-multilingual-mlx'
                        : selection == 'kev4'
                        ? 'jaredpalmer/kev-4b'
                        : 'deepseek-flash')
              : data['model'] != expected)) {
        throw StateError('模型尚未就绪或服务模型不匹配');
      }
      if (!mounted) return;
      api.close();
      api = JevClient(base, endpoint: '/v1/tool-decision');
      assistedPlayer = AssistedPlayer(
        api,
        uniformAssistance: true,
        correctChoices: tetrisShield,
      );
      setState(() {
        selectedModel = selection;
        modelName = data['model'];
        history = [];
        latency = null;
        lastChoice = '—';
        status = '已切换到 $modelName · 保留当前棋盘，重新选择方案';
      });
    } catch (e) {
      if (mounted) setState(() => status = '模型切换失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadReport() async {
    final records = <dynamic>[];
    try {
      records.add(
        jsonDecode(await rootBundle.loadString('reports/manual-baseline.json')),
      );
    } catch (_) {
      /* A manual baseline may not yet exist. */
    }
    try {
      final optimized = jsonDecode(
        await rootBundle.loadString(
          'reports/prompt-study/priority/benchmark.json',
        ),
      );
      for (final record in optimized['games']) {
        records.add({...record, 'game': '新提示词 · ${record['game']}'});
      }
    } catch (_) {
      /* The prompt experiment is optional. */
    }
    try {
      final r = await http.get(
        Uri.parse('${api.baseUrl}/reports/benchmark.json'),
      );
      if (r.statusCode == 200) records.addAll(jsonDecode(r.body)['games']);
    } catch (_) {
      /* The saved manual baseline works offline. */
    }
    if (mounted) setState(() => games = records);
  }

  String recordLabel(int index) =>
      games[index]['game'] == '手动基准' ? '手动基准' : '第 ${games[index]['game']} 局';

  @override
  void dispose() {
    replayTimer?.cancel();
    api.close();
    super.dispose();
  }

  void reset() {
    assistedPlayer.reset();
    epoch++;
    loopEpoch++;
    replayTimer?.cancel();
    setState(() {
      game = StepTetris(game.seed + 1);
      running = false;
      replayBoard = null;
      history = [];
      turns = 0;
      latency = null;
      confidence = null;
      lastChoice = '—';
      tetrisCorrections = 0;
      tetrisDecision = '尚无模型选择';
      status = '新一局 · 可手动或 AI 操作';
    });
  }

  void manual(String action) {
    if (busy || running || replayBoard != null) return;
    setState(() {
      final accepted = game.act(action);
      status = game.over
          ? '本局结束 · ${game.actions} 次动作 / ${game.steps} 块 / ${game.lines} 行'
          : accepted
          ? '已执行 $action · ${action == 'hard_drop' ? '直接落下并锁定' : '下落一格，受阻则锁定'}'
          : '动作受阻 · 方块位置不变';
    });
  }

  Future<void> directLand() async {
    if (busy ||
        running ||
        game.over ||
        replayBoard != null ||
        selectedModel == 'jev') {
      return;
    }
    final generation = epoch;
    final directApi = JevClient(api.baseUrl, endpoint: '/v1/land-decision');
    setState(() {
      busy = true;
      status = '模型正在选择直接落位目标…';
    });
    try {
      final plans = reachablePlans(game);
      final raw = await directApi.decide(uniformTetrisRequest(plans));
      final data = correctPlacement(plans, raw, enabled: tetrisShield);
      if (!mounted || generation != epoch) return;
      if (data['error'] != null) throw StateError(data['error']);
      final selected = plans.firstWhere((p) => p.id == data['choice']);
      setState(() {
        final count = landAtTarget(game, selected.id);
        recordCorrection(data);
        assistedPlayer.reset();
        turns++;
        latency = data['_http_ms'];
        modelName = data['model'];
        lastChoice =
            'land_at_target · 列 ${selected.outcome['column']} / 旋转 ${selected.outcome['rotation']}';
        status = game.over
            ? '本局结束 · ${game.score} 分'
            : '直接落位完成 · 等价 $count 步 · ${game.score} 分';
      });
    } catch (e) {
      if (mounted && generation == epoch) setState(() => status = '请求失败：$e');
    } finally {
      directApi.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> step() async {
    if (busy || replayBoard != null) return;
    if (game.over) {
      setState(() {
        running = false;
        status =
            '本局结束 · ${game.actions} 次动作 / ${game.steps} 块 / ${game.lines} 行';
      });
      return;
    }
    final generation = epoch;
    setState(() {
      busy = true;
      status = selectedModel == 'jev'
          ? 'JEV 正在读取棋盘并选择一个原始动作…'
          : '正在准备方案 · 模型选择落点，程序逐格执行…';
    });
    try {
      final data = selectedModel == 'jev'
          ? await decideRawTetris(api, game)
          : await assistedPlayer.decide(game);
      if (!mounted || generation != epoch) return;
      if (data['error'] != null) throw StateError(data['error']);
      final plan = List<String>.from(data['actions']);
      final execution = TurnExecutor(game, plan);
      setState(() {
        turns++;
        recordCorrection(data);
        modelName = data['model'] as String;
        latency = data['_http_ms'];
        confidence = null;
        lastChoice = selectedModel == 'jev'
            ? '原始动作：${data['choice']}'
            : '目标列 ${data['predicted_outcome']['column']} / 旋转 ${data['predicted_outcome']['rotation']} / 预计消 ${data['predicted_outcome']['lines_cleared']} 行\n本批：${plan.join(' → ')}';
      });
      while (mounted && generation == epoch && execution.advance()) {
        setState(
          () =>
              status = '回合 $turns · 已执行 ${execution.executed}/${plan.length} 步',
        );
        if (execution.stopReason == null) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      if (!mounted || generation != epoch) return;
      if (selectedModel != 'jev') assistedPlayer.observe(game, execution);
      setState(() {
        history.insert(0, {
          'step': turns,
          'choice':
              '${execution.executed}/${plan.length} 步${data['continued_plan'] == true ? ' · 续执行' : ' · 模型选择'}',
          'ms': latency,
        });
        if (history.length > 8) history.removeLast();
        status = game.over
            ? '本局结束 · ${game.steps} 块 / ${game.lines} 行'
            : execution.stopReason == 'invalid_action'
            ? '动作受阻 · 剩余序列已取消'
            : execution.stopReason == 'piece_locked'
            ? '方块已锁定 · 剩余序列已取消'
            : '回合 $turns 完成 · ${execution.executed} 步';
        if (selectedModel == 'jev' && execution.executed == 0) {
          tetrisDecision = '原始：${data['choice']} → 未执行：动作受阻；无替代动作';
        }
        if (game.over || execution.executed == 0) running = false;
      });
    } catch (e) {
      if (mounted && generation == epoch) {
        setState(() {
          running = false;
          status = '请求失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle() async {
    final loop = ++loopEpoch;
    if (running) {
      epoch++;
      setState(() {
        running = false;
        status = '已暂停 · 未执行动作已取消';
      });
      return;
    }
    replayTimer?.cancel();
    setState(() {
      replayBoard = null;
      running = true;
    });
    while (mounted && running && loop == loopEpoch) {
      await step();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void replay(int index) {
    if (busy) return;
    epoch++;
    loopEpoch++;
    running = false;
    replayTimer?.cancel();
    replayIndex = 0;
    replayGame = index;
    final frames = games[index]['frames'] as List;
    void tick() {
      if (!mounted) return;
      if (replayIndex >= frames.length) {
        replayTimer?.cancel();
        return;
      }
      final f = frames[replayIndex++];
      setState(() {
        replayBoard = (f['board'] as List)
            .map((r) => List<int>.from(r))
            .toList();
        latency = (f['http_ms'] as num?)?.toDouble();
        confidence = (f['confidence'] as num?)?.toDouble();
        lastChoice = f['choice'];
        status =
            '实测回放 · ${recordLabel(index)} · ${f['step']} / ${frames.length} 步';
      });
    }

    tick();
    replayTimer = Timer.periodic(
      const Duration(milliseconds: 220),
      (_) => tick(),
    );
  }

  Widget panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xff111d2e),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xff243249)),
    ),
    child: child,
  );
  Widget metric(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final board = replayBoard ?? game.displayBoard;
    final frame = replayBoard == null
        ? null
        : games[replayGame]['frames'][replayIndex - 1];
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.grid_view_rounded,
                        color: Color(0xff71e4ac),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'QWEN / TETRIS LAB',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      Chip(
                        label: Text(
                          modelName.startsWith('jev-')
                              ? 'CLOUD · JEV'
                              : modelName.contains('laya-')
                              ? 'LOCAL MLX · Laya Multilingual 322M'
                              : modelName.contains('kev-4b')
                              ? 'LOCAL MPS · Kev 4B'
                              : modelName.contains('deepseek')
                              ? 'CLOUD · DeepSeek Flash'
                              : modelName.contains('4B')
                              ? 'LOCAL MLX · 4B'
                              : modelName.contains('0.8B')
                              ? 'LOCAL MLX · 0.8B'
                              : 'MLX · 未连接',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '让小模型，下一步。',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '辅助规划 · 模型选方案 / 每批最多 8 步',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedModel,
                    key: ValueKey(selectedModel),
                    decoration: const InputDecoration(
                      labelText: 'AI 模型',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'laya',
                        child: Text('Laya Multilingual 322M · 本地 MLX 决策模型'),
                      ),
                      DropdownMenuItem(
                        value: 'kev4',
                        child: Text('Kev-4B · 本地 MPS 决策模型'),
                      ),
                      DropdownMenuItem(
                        value: 'qwen08',
                        child: Text('Qwen3.5-0.8B · 本地 MLX'),
                      ),
                      DropdownMenuItem(
                        value: 'qwen4',
                        child: Text('Qwen3.5-4B · 本地 MLX'),
                      ),
                      DropdownMenuItem(
                        value: 'jev',
                        child: Text('JEV · 云端 API'),
                      ),
                      DropdownMenuItem(
                        value: 'deepseek',
                        child: Text('DeepSeek Flash · 云端 API'),
                      ),
                    ],
                    onChanged: busy || running ? null : selectModel,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '切换保留棋盘并清空待执行方案；自动运行时先暂停。DeepSeek / JEV 会将游戏局面发送至云端 API。',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, c) {
                      final arena = panel(
                        Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  replayBoard == null
                                      ? 'LIVE ARENA'
                                      : 'BENCHMARK REPLAY',
                                  style: const TextStyle(
                                    letterSpacing: 2,
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  replayBoard == null
                                      ? 'NEXT  ${game.next}'
                                      : recordLabel(replayGame),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 460,
                              width: 230,
                              child: CustomPaint(
                                painter: BoardPainter(
                                  board,
                                  replayBoard == null ? game.ghost : null,
                                  game.piece,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              '逐格操作 / hard_drop 直接落下 · 无踢墙',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  tooltip: '左移',
                                  onPressed: () => manual('left'),
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                IconButton(
                                  tooltip: '旋转',
                                  onPressed: () => manual('rotate'),
                                  icon: const Icon(Icons.rotate_right),
                                ),
                                IconButton(
                                  tooltip: '右移',
                                  onPressed: () => manual('right'),
                                  icon: const Icon(Icons.arrow_forward),
                                ),
                                IconButton(
                                  tooltip: '下落一步',
                                  onPressed: () => manual('down'),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                IconButton(
                                  tooltip: '直接落下',
                                  onPressed: () => manual('hard_drop'),
                                  icon: const Icon(Icons.vertical_align_bottom),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      final controls = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '本局表现',
                                  style: TextStyle(color: Colors.white54),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    metric(
                                      '已锁定方块',
                                      '${frame?['step'] ?? game.steps}',
                                    ),
                                    metric(
                                      '消除行数',
                                      '${frame?['total_lines'] ?? game.lines}',
                                    ),
                                    metric(
                                      'HTTP 耗时',
                                      latency == null
                                          ? '—'
                                          : '${latency!.round()} ms',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: toggle,
                                      icon: Icon(
                                        running
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      label: Text(running ? '暂停 AI' : 'AI 自动玩'),
                                    ),
                                    OutlinedButton(
                                      onPressed: busy || running ? null : step,
                                      child: const Text('AI 一回合'),
                                    ),
                                    OutlinedButton(
                                      onPressed:
                                          busy ||
                                              running ||
                                              game.over ||
                                              selectedModel == 'jev'
                                          ? null
                                          : directLand,
                                      child: const Text('AI 直接落位'),
                                    ),
                                    TextButton(
                                      onPressed: reset,
                                      child: const Text('新一局'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: status.startsWith('请求失败')
                                        ? Colors.redAccent
                                        : const Color(0xff71e4ac),
                                  ),
                                ),
                                if (busy) const LinearProgressIndicator(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '决策观察',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Material(
                                  color: Colors.transparent,
                                  child: SwitchListTile(
                                    title: const Text('统一落点辅助'),
                                    subtitle: Text(
                                      selectedModel == 'jev'
                                          ? 'JEV 固定无辅助：原始棋盘、单步动作，无落点规划或纠错'
                                          : '本地模型与 DeepSeek 使用候选评价；关闭只停用动作改写',
                                    ),
                                    value: selectedModel == 'jev'
                                        ? false
                                        : tetrisShield,
                                    onChanged:
                                        busy ||
                                            running ||
                                            replayBoard != null ||
                                            selectedModel == 'jev'
                                        ? null
                                        : (v) => setState(() {
                                            tetrisShield = v;
                                            assistedPlayer = AssistedPlayer(
                                              api,
                                              uniformAssistance: true,
                                              correctChoices: v,
                                            );
                                            tetrisDecision = '辅助已切换 · 待执行方案已清空';
                                          }),
                                  ),
                                ),
                                Text(
                                  '$tetrisDecision · 本局纠错 $tetrisCorrections 次',
                                ),
                                Text('计划 $lastChoice'),
                                const SizedBox(height: 8),
                                Text(
                                  selectedModel == 'jev'
                                      ? 'JEV 每次只接收原始棋盘、规则及动作含义；不枚举落点，不预测或排序结果，不纠错。AI 直接落位禁用，模型仍可自行选择 hard_drop。动作受阻时暂停，不替换动作。'
                                      : '程序枚举全部可达落点并预测结果；Laya / Kev 直接输出候选概率，其他模型用工具选择。所有模型收到相同的程序落点评价；辅助开启时按存活、消行、空洞、高度、起伏顺序纠错，不使用模型概率。每批最多执行 8 步，同一方块沿用选定方案；锁定后重新选择。辅助模式关闭长思考，0 ms 表示续执行，无新模型请求。',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    height: 1.6,
                                  ),
                                ),
                                const Divider(height: 28),
                                for (final h in history)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Text('#${h['step']}'),
                                        const SizedBox(width: 20),
                                        Text(h['choice']),
                                        const Spacer(),
                                        Text(
                                          '${(h['ms'] as double).round()} ms',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '得分：${game.score} · AI 回合：$turns · 动作次数：${game.actions}\n普通动作推进一格；hard_drop 直接落下锁定\n固定种子 / 七袋随机 / 无自动计时 / 无踢墙',
                            style: TextStyle(
                              color: Colors.white38,
                              height: 1.8,
                            ),
                          ),
                        ],
                      );
                      return c.maxWidth > 760
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 340, child: arena),
                                const SizedBox(width: 24),
                                Expanded(child: controls),
                              ],
                            )
                          : Column(
                              children: [
                                arena,
                                const SizedBox(height: 16),
                                controls,
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Text(
                        '旧版硬降基准与历史实测',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: loadReport,
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (games.isEmpty)
                    const Text(
                      '评测完成后在此查看并回放。运行 dart run tool/benchmark.dart。',
                      style: TextStyle(color: Colors.white54),
                    ),
                  if (games.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('局数')),
                          DataColumn(label: Text('落块数')),
                          DataColumn(label: Text('消行')),
                          DataColumn(label: Text('启发式步数')),
                          DataColumn(label: Text('随机步数')),
                          DataColumn(label: Text('结束')),
                          DataColumn(label: Text('回放')),
                        ],
                        rows: [
                          for (var i = 0; i < games.length; i++)
                            DataRow(
                              cells: [
                                DataCell(Text('${games[i]['game']}')),
                                DataCell(Text('${games[i]['steps']}')),
                                DataCell(Text('${games[i]['lines']}')),
                                DataCell(
                                  Text('${games[i]['baseline_steps'] ?? '—'}'),
                                ),
                                DataCell(
                                  Text('${games[i]['random_steps'] ?? '—'}'),
                                ),
                                DataCell(
                                  Text(
                                    games[i]['end_reason'] == 'top_out'
                                        ? '堆顶'
                                        : '上限',
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    tooltip: '回放${recordLabel(i)}',
                                    onPressed: busy ? null : () => replay(i),
                                    icon: const Icon(Icons.replay),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    selectedModel == 'jev'
                        ? '$modelName / TypeSafe 官方云端 API'
                        : '$modelName / 本地兼容实现，非 TypeSafe Jev 原模型',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BoardPainter extends CustomPainter {
  final List<List<int>> board;
  final Placement? ghost;
  final String piece;
  BoardPainter(this.board, this.ghost, this.piece);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / width, h = size.height / height;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x * w + 1, y * h + 1, w - 2, h - 2),
          const Radius.circular(3),
        );
        canvas.drawRRect(rect, Paint()..color = colors[board[y][x]]);
        if (board[y][x] > 0) {
          canvas.drawLine(
            Offset(x * w + 4, y * h + 4),
            Offset((x + 1) * w - 4, y * h + 4),
            Paint()
              ..color = Colors.white30
              ..strokeWidth = 2,
          );
        }
      }
    }
    if (ghost != null) {
      for (final p in rotations(piece)[ghost!.rotation]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              (ghost!.x + p[0]) * w + 2,
              (ghost!.y + p[1]) * h + 2,
              w - 4,
              h - 4,
            ),
            const Radius.circular(3),
          ),
          Paint()
            ..color = const Color(0xff71e4ac)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}

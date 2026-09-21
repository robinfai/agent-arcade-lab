"""Summarize paired decision-v1 runs without treating order repeats as independent seeds."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    root = args.root
    meta = json.loads((root / 'metadata.json').read_text())
    rows = [json.loads(p.read_text()) for p in sorted((root / 'runs').glob('*/*/*/*/summary.json'))]
    expected = len(meta['seeds']) * len(meta['order_seeds']) * (2 + len(meta['models'])) * 2
    if len(rows) != expected:
        raise SystemExit(f'Incomplete: {len(rows)}/{expected}; final report not written.')
    indexed = {(r['seed'], r['order_seed'], r['label'], r['game']): r for r in rows}
    assert len(indexed) == expected
    checked_laya = checked_qwen = 0
    for p in sorted((root / 'runs').glob('*/*/*/*/trace.jsonl')):
        for line in p.open():
            item = json.loads(line)
            assert item['corrected'] is False
            if item['executed_actions']:
                assert item['proposed'] == item['executed_choice']
            response = item['response']
            if p.parent.parent.name == 'laya' and response.get('model_input'):
                assert response['model_input'] == {k: item['request'][k] for k in ['state', 'questions']}
                assert response['input_budget']['truncated'] is False
                checked_laya += 1
            if p.parent.parent.name == 'qwen08' and item['executed_actions']:
                assert response['constrained_decoding'] is True
                checked_qwen += 1
    for seed in meta['seeds']:
        for label in ['random', 'program']:
            for game in ['snake', 'tetris']:
                trajectories = []
                for order in meta['order_seeds']:
                    path = root/'runs'/str(seed)/str(order)/label/game/'trace.jsonl'
                    trajectories.append([json.loads(line)['after'] for line in path.open()])
                assert all(t == trajectories[0] for t in trajectories)

    lines = ['# decision-v1：相同候选下的真实模型对照', '',
             '模型只看到完整状态、规则和共同合法候选，不接收评价或最佳标签；直接执行原始选择，无纠错、无重试。合法候选枚举和路径执行仍由程序提供，因此不是完全无辅助测试。', '',
             f"游戏种子：{meta['seeds']}；展示种子：{meta['order_seeds']}。每局最多 {meta['max_steps']} 动作/请求；展示重复不算新增独立游戏种子。", '',
             '## 每局结果', '',
             '| 游戏种子 | 展示种子 | 策略 | 游戏 | 动作 | 得分 | 比程序 | 比随机 | 落块/消行 | 请求 | 终止原因 |',
             '| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- |']
    for r in rows:
        seed, order, game = r['seed'], r['order_seed'], r['game']
        program = indexed[seed, order, 'program', game]
        random = indexed[seed, order, 'random', game]
        state = r['final_state']
        counts = f"{state['pieces']}/{state['lines']}" if game == 'tetris' else '—'
        delta_program = '—' if r['error'] else f"{r['score']-program['score']:+d}"
        delta_random = '—' if r['error'] else f"{r['score']-random['score']:+d}"
        score = '未执行' if r['error'] and not r['steps'] else str(r['score'])
        lines.append(f"| {seed} | {order} | {r['label']} | {game} | {r['steps']} | {score} | {delta_program} | {delta_random} | {counts} | {r['requests']} | {r['end_reason']} |")
    lines += ['', '请求或协议失败不计算策略分差；得分仅为中断时进度，首步失败记为未执行。受困（no_legal_actions）表示没有合法下一步，不是存活完成。达到上限不证明无限存活。', '',
              '## 展示排列敏感性', '', '| 模型 | 游戏种子 | 游戏 | 各展示种子的得分 | 各展示种子的终止原因 |', '| --- | --- | --- | --- | --- |']
    for label in meta['models']:
        for seed in meta['seeds']:
            for game in ['tetris', 'snake']:
                selected = [indexed[seed, order, label, game] for order in meta['order_seeds']]
                lines.append(f"| {label} | {seed} | {game} | {', '.join(str(r['score']) if not r['error'] else '中断' for r in selected)} | {', '.join(r['end_reason'] for r in selected)} |")
    lines += ['', '## 请求失败现场', '']
    for r in rows:
        if r['error']:
            lines.append(f"- {r['seed']}/{r['order_seed']}/{r['label']}/{r['game']}：已执行 {r['steps']} 步；{r['error']}")
    lines += ['', '候选顺序与编号共同置换，变化属于展示敏感性；云端非确定性也可能参与，单次重复不能将差异全归因于顺序。', '',
              '## 调用与终止', '', '| 模型 | 请求总数 | 到达动作上限 | 请求/协议/执行错误 | 实际模型 |', '| --- | ---: | --- | ---: | --- |']
    for label in ['random', 'program'] + meta['models']:
        selected = [r for r in rows if r['label'] == label]
        failures = [r for r in selected if r['error'] is not None]
        lines.append(f"| {label} | {sum(r['requests'] for r in selected)} | {sum(r['end_reason']=='step_cap' for r in selected)}/{len(selected)} | {len(failures)} | {', '.join(sorted({str(r['model']) for r in selected}))} |")
    lines += ['', '三个游戏种子仅提供探索性证据，不作统计显著性判断。各策略走出不同轨迹后，模型面对的实际局面也不同；对照的是共同规则和初始条件下的整局结果。', '',
              '离线核验：', '', '```text', (root/'verification.txt').read_text().strip().splitlines()[-1], '```', '',
              '逐步证据见 runs/；配置、模型健康信息和源码哈希见 metadata.json，源码副本见 source/。未进行浏览器端到端验收。', '']
    lines += [f'补充核对：{checked_laya} 次 Laya 响应完整保留输入且未截断；{checked_qwen} 次 Qwen 执行响应确认格式约束。所有轨迹无纠错，随机/程序在不同展示排列下逐帧一致。', '']
    if (root/'parallel-status.json').exists():
        lines += ['调度记录：起初串行，按用户要求中途切换为 JEV 单独串行、其余本地模型和基线在第二队列串行，两队列并行。原始局未重跑，起始配置见 metadata.json，切换记录见 parallel-status.json。不据此比较公平延迟。', '']
    (root/'README.md').write_text('\n'.join(lines))
    print(root/'README.md')


if __name__ == '__main__':
    main()

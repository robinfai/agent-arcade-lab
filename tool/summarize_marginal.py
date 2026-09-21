"""Describe paired score differences without claiming significance from three seeds."""
import argparse
import json
from pathlib import Path
import statistics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    root = args.root
    metadata = json.loads((root / 'metadata.json').read_text())
    rows = [json.loads(p.read_text()) for p in sorted((root / 'runs').glob('*/*/*/summary.json'))]
    expected = len(metadata['seeds']) * 8
    if len(rows) != expected:
        raise SystemExit(f'Incomplete: {len(rows)}/{expected} runs; no final report written.')
    indexed = {(r['seed'], r['label'], r['game']): r for r in rows}
    lines = ['# 2000 步：模型相对纯程序的增益验证', '',
             '3 个固定种子，每个种子两个游戏；纯程序、JEV、Laya、Qwen 0.8B 各一局，共 24 局。每局最多 2000 个实际动作和 2000 次模型请求，3600 秒预算检查。', '',
             'Qwen 使用新实现的强制工具格式（explicit-tool + required-tool），保留全部候选。它改变了解码条件，因此本报告单独统计，不替换历史自由输出结果。', '',
             '以下均为系统结果：模型组包含候选规划、最佳标签和执行纠错。每个种子只跑一次，不计算显著性、不宣称稳定优势。', '',
             '## 每局结果', '', '| 种子 | 模型 | 游戏 | 实际动作 | 得分 | 相对程序分差 | 请求 | 纠错 | 终止原因 |',
             '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |']
    for r in rows:
        baseline = indexed[r['seed'], 'program', r['game']]
        delta = r['score'] - baseline['score']
        lines.append(f"| {r['seed']} | {r['label']} | {r['game']} | {r['steps']} | {r['score']} | {delta:+d} | {r['requests']} | {r['corrections']} | {r['end_reason']} |")
    lines += ['', '## 配对得分变化', '',
              '胜/平/负仅表示最终得分比较，不是游戏胜率。提前错误属于系统失败，其得分仍列出；不能据此单独归因于策略能力。', '',
              '| 模型 | 游戏 | 三个种子的分差（含中断） | 系统平均分差 | 完整局平均分差 | 胜/平/负 | 跑满预算 |',
              '| --- | --- | --- | ---: | ---: | --- | --- |']
    for label in ['jev', 'laya', 'qwen08']:
        for game in ['tetris', 'snake']:
            selected = [indexed[seed, label, game] for seed in metadata['seeds']]
            deltas = [r['score'] - indexed[r['seed'], 'program', game]['score'] for r in selected]
            counts = [sum(d > 0 for d in deltas), sum(d == 0 for d in deltas), sum(d < 0 for d in deltas)]
            caps = sum(r['end_reason'] == 'step_cap' for r in selected)
            complete_deltas = [delta for row, delta in zip(selected, deltas) if row['end_reason'] == 'step_cap']
            complete_mean = f'{statistics.mean(complete_deltas):+.1f}' if complete_deltas else '无完整局'
            lines.append(f"| {label} | {game} | {', '.join(f'{d:+d}' for d in deltas)} | {statistics.mean(deltas):+.1f} | {complete_mean} | {'/'.join(map(str, counts))} | {caps}/{len(selected)} |")
    lines += ['', '完整局均值只包含达到动作上限的配对，存在完成者筛选，不能代替系统失败率；中断前的成绩也不能与 2000 步成绩当作等预算策略比较。', '',
              '### 蛇局在相同已执行步数处的比较', '',
              '| 模型 | 种子 | 已执行步数 | 此时模型分数 | 纯程序同一步分数 | 与程序状态完全相同的帧数 |',
              '| --- | --- | ---: | ---: | ---: | ---: |']
    for label in ['jev', 'laya', 'qwen08']:
        for seed in metadata['seeds']:
            baseline_rows = [json.loads(line) for line in (root / 'runs' / str(seed) / 'program/snake/trace.jsonl').open()]
            model_rows = [json.loads(line) for line in (root / 'runs' / str(seed) / label / 'snake/trace.jsonl').open()]
            actual = [row for row in model_rows if row['executed_actions']]
            if not actual:
                continue
            steps = actual[-1]['after']['frame']
            same = sum(a['after'] == b['after'] for a, b in zip(actual, baseline_rows))
            lines.append(f"| {label} | {seed} | {steps} | {actual[-1]['after']['score']} | {baseline_rows[steps-1]['after']['score']} | {same}/{steps} |")
    lines += ['', '## 模型实际可改变的选择', '',
              '有辅助方块不给原始棋盘，只给程序产生的候选标签和局部指标；严格劣于程序最佳值的提议会被纠正。因此，最终执行与纯程序分叉的来源是多个并列最佳落点间的选择，不能将分差直接解释为模型完成了更好的棋盘规划。', '',
              '| 模型 | 方块决策总数 | 多个并列最佳候选的回合 | 执行非首个并列最佳候选 |',
              '| --- | ---: | ---: | ---: |']
    for label in ['program', 'jev', 'laya', 'qwen08']:
        count = ties = alternatives = 0
        for path in sorted((root / 'runs').glob(f'*/{label}/tetris/trace.jsonl')):
            for line in path.open():
                row = json.loads(line)
                best = [key for key, value in row['request']['questions']['move']['criteria'].items()
                        if 'Best placement.' in value]
                count += 1
                ties += len(best) > 1
                alternatives += bool(best and row['executed'] in best and row['executed'] != best[0])
        lines.append(f'| {label} | {count} | {ties} | {alternatives} |')
    lines += ['', '这一设计能检验当前接入方式的系统增益，但不代表模型的完整规划能力。要区分并列选项偏好与可泛化的策略增益，需要增加随机或固定不同顺序的并列选择基线。', '', '## 调用与验证', '',
              '| 模型 | 总请求 | 报告输入 token | 报告输出 token | 实际模型 |',
              '| --- | ---: | ---: | ---: | --- |']
    for label in ['program', 'jev', 'laya', 'qwen08']:
        selected = [r for r in rows if r['label'] == label]
        lines.append(f"| {label} | {sum(r['requests'] for r in selected)} | {sum(r['input_tokens'] for r in selected)} | {sum(r['output_tokens'] for r in selected)} | {', '.join(sorted({str(r['model']) for r in selected}))} |")
    lines += ['', 'Token 按后端报告记录，决策头与自回归模型口径不同，不能直接比较成本；未查询价格，不估算费用。云端三种子并发，本地模型串行，不提供公平延迟排名。', '',
              '原始轨迹见 `runs/`，配置及源码哈希见 `metadata.json`，源码副本见 `source/`。旧报告未覆盖。', '',
              '离线核验结果（完整逐局输出见 `verification.txt`）：', '', '```text', (root / 'verification.txt').read_text().strip().splitlines()[-1], '```', '',
              '未进行浏览器端到端验证。达到 2000 步属于截尾观察，不证明无限存活；同一模型在不同种子获益方向一致，也仍需更多独立种子和预先固定的统计方案确认。', '']
    (root / 'README.md').write_text('\n'.join(lines))
    print(root / 'README.md')


if __name__ == '__main__':
    main()

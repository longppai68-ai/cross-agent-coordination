#!/bin/bash
# 冲突检测 —— 针对「缺口①：无并发保护」
# 检测：① 不同作者写入过近（真并发窗口）② 日志物理顺序 ≠ 时间顺序 ③ 半截行/格式异常 ④ 表格列数不一致
# 用法: bash 冲突检测.sh [交接文件]      # 缺省读同目录下的 工作协调.md
DIR="$(cd "$(dirname "$0")" && pwd)"
F="${1:-$DIR/工作协调.md}"
[ -f "$F" ] || { echo "找不到 $F"; exit 1; }

echo "=== 冲突检测  $(date '+%F %T')  ==="
echo "  目标: $(basename "$F")  ($(wc -c < "$F" | tr -d ' ') 字节)"

python3 - "$F" <<'PY'
import re, sys, datetime, os
path = sys.argv[1]
lines = open(path, encoding='utf-8').read().split('\n')

# 解析条目头：### YYYY-MM-DD HH:MM[:SS] ｜ 作者 → 类型
ent = []
for i, l in enumerate(lines, 1):
    m = re.match(r'^###\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}(?::\d{2})?)\s*｜\s*(\S+?)\s*→\s*(\S+)', l)
    if m:
        ts, author, kind = m.group(1), m.group(2), m.group(3)
        fmt = '%Y-%m-%d %H:%M:%S' if ts.count(':') == 2 else '%Y-%m-%d %H:%M'
        try:
            t = datetime.datetime.strptime(ts, fmt)
        except ValueError:
            continue
        ent.append({'line': i, 'ts': ts, 't': t, 'author': author, 'kind': kind})

print(f"  条目总数: {len(ent)}")

# ① 跨作者邻近写入（按物理顺序）
same_min, near = [], []
for a, b in zip(ent, ent[1:]):
    if a['author'] != b['author']:
        gap = (b['t'] - a['t']).total_seconds()
        if gap == 0:
            same_min.append((a, b))
        elif abs(gap) <= 120:
            near.append((gap, a, b))
if same_min:
    print(f"  ⚠️ 跨作者「同一分钟」相邻条目 {len(same_min)} 处 —— 分钟精度下的真实并发窗口")
    for a, b in same_min[:5]:
        print(f"       行{a['line']:>4} {a['ts']} {a['author']}   ‖   行{b['line']:>4} {b['ts']} {b['author']}")
else:
    print("  ✅ 无跨作者「同一分钟」写入")
if near:
    print(f"  ℹ️ 跨作者间隔 1–2 分钟的相邻条目 {len(near)} 处（通常只是快速往返，非并发）")

# ② 物理顺序 vs 时间顺序
inv = [(a, b) for a, b in zip(ent, ent[1:]) if b['t'] < a['t']]
if inv:
    print(f"  ⚠️ 时间倒挂 {len(inv)} 处（物理顺序 ≠ 时间顺序）→ 不能假设「文件末尾 = 最新」")
    for a, b in inv[:5]:
        print(f"       行{a['line']:>4} {a['ts']} {a['author']}  ←  行{b['line']:>4} {b['ts']} {b['author']}")
else:
    print("  ✅ 物理顺序与时间顺序一致")

# 内容时间戳的精度
with_w = sum(1 for l in lines if re.search(r'（写于 \d{1,2}:\d{2}:\d{2}）', l))
print(f"  带「写于 HH:MM:SS」的条目: {with_w}/{len(ent)}  →  " +
      ("可做秒级碰撞检测" if with_w else "仅分钟级精度，无法精确定位碰撞（建议条目加「写于 HH:MM:SS」）"))

# ③ 半截行 / 格式异常
bad = []
tail = '\n'.join(lines).rstrip('\n')
if lines and lines[-1].strip() != '' and not lines[-1].startswith(('*', '-', '|', '>', '#', ' ')):
    bad.append(('末行可能被截断', lines[-1][:60]))
for i, l in enumerate(lines, 1):
    if not l.startswith('###'):
        continue
    # 合法：编号小标题（### 1.2 xxx）、模板行（含 <作者>）、正常条目头
    if re.match(r'^###\s+[\d.]+\s', l):
        continue
    if '<作者>' in l or '<方>' in l:
        continue
    if re.match(r'^###\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}', l):
        continue
    # 只把「看起来像条目头（含 ｜ 且有 →）但时间戳不合法」的判为异常
    if '｜' in l and '→' in l and not re.match(r'^###\s+<YYYY', l):
        bad.append((f'行{i} 条目头时间戳不合法', l[:60]))
if bad:
    print(f"  ⚠️ 疑似损坏/异常 {len(bad)} 处:")
    for k, v in bad[:5]:
        print(f"       {k}: {v}")
else:
    print("  ✅ 未发现半截行或标题格式异常")

# ④ 表格完整性（Markdown 表格被截断会让整段渲染成游离文本）
from collections import Counter
blocks, cur = [], []
for i, l in enumerate(lines, 1):
    if l.startswith('|'):
        cur.append((i, l))
    else:
        if cur: blocks.append(cur); cur = []
if cur: blocks.append(cur)
tbl_bad = []
for b in blocks:
    cnt = [(i, l.count('|') - 1) for i, l in b]
    if len(cnt) < 2:
        continue
    mode = Counter(c for _, c in cnt).most_common(1)[0][0]
    for i, c in cnt:
        if c != mode:
            tbl_bad.append((i, c, mode))
if tbl_bad:
    print(f"  ⚠️ 表格列数不一致 {len(tbl_bad)} 处（多数列为基准）:")
    for i, c, m in tbl_bad[:6]:
        print(f"       行{i:>4} 有 {c} 列，同表多数为 {m} 列 → 表格会被截断")
else:
    print(f"  ✅ 表格完整性正常（检查了 {len(blocks)} 个表格块）")

# 结论建议
print()
if near or inv:
    print("  ▶ 建议：启用「追加即一切」——状态板改为快照行（last-write-wins），禁止就地编辑；")
    if with_w == 0:
        print("          条目同时记录「写于 HH:MM:SS」以支撑秒级碰撞检测。")
else:
    print("  ▶ 当前风险低，但机制缺口仍在：建议按指导书 §十 的前两级改造。")
PY

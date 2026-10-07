#!/bin/bash
# 人类待办横幅 —— 针对「缺口④：人类通道最弱」
# 作用：把"必须人做、且有死线"的动作渲染成①一行可置顶的横幅 ②带倒计时与后果的清单
# 用法: bash 人类待办横幅.sh           # 横幅 + 明细
#       bash 人类待办横幅.sh --banner  # 只输出一行横幅（供 Agent 回复置顶）
DIR="$(cd "$(dirname "$0")" && pwd)"
F="$DIR/人类待办.tsv"
[ -f "$F" ] || { echo "找不到 $F"; exit 1; }

python3 - "$F" "$1" <<'PY'
import sys, datetime
path, mode = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else '')
now = datetime.datetime.now()
rows = []
for ln in open(path, encoding='utf-8'):
    ln = ln.rstrip('\n')
    if not ln.strip() or ln.startswith('#'):
        continue
    parts = ln.split('\t')
    if len(parts) < 4:
        continue
    rid, action, dl, consequence = parts[0], parts[1], parts[2], parts[3]
    try:
        dt = datetime.datetime.strptime(dl.strip(), '%Y-%m-%d %H:%M')
    except ValueError:
        continue
    rem = (dt - now).total_seconds()
    if rem < 0:
        level, mark = 3, '🔴 已逾期'
    elif rem <= 86400:
        level, mark = 2, '🚨 24小时内'
    elif rem <= 3 * 86400:
        level, mark = 1, '⚠️ 3天内'
    else:
        level, mark = 0, 'ℹ️ 尚早'
    rows.append({'id': rid, 'action': action, 'dl': dt, 'rem': rem,
                 'level': level, 'mark': mark, 'cons': consequence})

# 紧迫度：level 越大越紧急 → 降序；同级别按剩余时间升序
# 紧迫度：level 越大越紧急 → 降序；同级别按剩余时间升序
rows.sort(key=lambda r: (-r['level'], r['rem']))
def human(sec):
    if sec < 0:
        s = -sec
        return f"逾期 {int(s//3600)} 小时"
    h = int(sec // 3600)
    d, h = divmod(h, 24)
    return f"剩 {d}天{h}小时" if d else f"剩 {h}小时{int((sec%3600)//60)}分"

# ---- 一行横幅（供 Agent 回复置顶） ----
if rows:
    top = rows[0]
    others = [r for r in rows[1:]]
    act = top['action']
    act = act[:26] + '…' if len(act) > 26 else act
    banner = f"⏰ 人类侧待办 {len(rows)} 项未完成｜最紧：{top['id']} {act} → {human(top['rem'])}（{top['dl'].strftime('%m/%d %H:%M')}）"
    if others:
        banner += f"｜另有 {len(others)} 项"
    print(banner) if mode == '--banner' else None
    if mode != '--banner':
        print(f"[横幅] {banner}")
        print()

if mode == '--banner':
    sys.exit(0)

print(f"=== 人类待办  {now.strftime('%Y-%m-%d %H:%M')} ===")
print("  （自动机制覆盖不到这些——只有人能完成；下面是「卡住会怎样」）")
print()
for r in rows:
    print(f"  {r['mark']}  {r['id']}  {human(r['rem']):<14} 死线 {r['dl'].strftime('%Y-%m-%d %H:%M')}")
    print(f"       动作：{r['action']}")
    print(f"       后果：{r['cons']}")
    print()
if not rows:
    print("  ✅ 无人类侧待办")
print("  提示：只要上面非空，Agent 的每条回复开头都应带横幅（见指导书 §十一 H4）")
PY

#!/bin/bash
# 心跳检查（模板）—— 判断各参与方是否在线，把"沉默"变成可判断的信号
#
# 用法：
#   ① 修改下面的 AGENTS 数组（阈值 = 该方心跳间隔 × 2）
#   ② 与本文件同目录放置 工作协调.md / .watch_marker / .hb_<方>
#   ③ bash 心跳检查.sh
#
# 判读语义（三态）：
#   心跳✅ + 无未处理写入 → 在线且无消息（真·平静）
#   心跳✅ + 有未处理写入 → 在线且有事等我（配合监视器报警）
#   心跳❌               → 疑似离线（此前完全不可见，最危险）

DIR="$(cd "$(dirname "$0")" && pwd)"

# ===== 配置区 =====
# 格式: "显示名|心跳文件名|阈值分钟"
AGENTS=(
  "A|.hb_A|11"
  "B|.hb_B|22"
)
WATCH_MARKER=".watch_marker"     # 监视基线文件名（留空则跳过未处理项检查）
COORD_FILE="工作协调.md"          # 交接文件名
# ==================

now=$(date +%s)

echo "=== 心跳检查  $(date '+%F %T') ==="

for item in "${AGENTS[@]}"; do
  IFS='|' read -r name hbfile limit <<< "$item"
  f="$DIR/$hbfile"
  if [ ! -f "$f" ]; then
    printf "  %-6s ❌ 无心跳文件（从未写过）→ 在线与否不可判\n" "$name"
    continue
  fi
  mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
  age=$(( (now - mt) / 60 ))
  content=$(head -1 "$f" 2>/dev/null)
  if [ "$age" -le "$limit" ]; then
    printf "  %-6s ✅ 在线   （%s 分钟前心跳 / 阈值 %s）  %s\n" "$name" "$age" "$limit" "$content"
  else
    printf "  %-6s ⚠️ 疑似离线（已 %s 分钟无心跳 / 阈值 %s）  最后: %s\n" "$name" "$age" "$limit" "$content"
  fi
done

# ---- 未处理写入（配合持久基线） ----
if [ ! -f "$DIR/$COORD_FILE" ]; then
  printf "  %-6s ⚠️ 未找到 %s → 请把本脚本与交接文件放在同一目录\n" "" "$COORD_FILE"
fi
if [ -n "$WATCH_MARKER" ] && [ -f "$DIR/$WATCH_MARKER" ]; then
  pending=""
  for f in "$DIR"/*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "$COORD_FILE" ] || continue
    if [ "$f" -nt "$DIR/$WATCH_MARKER" ]; then pending="$b"; fi
  done
  if [ -n "$pending" ]; then
    printf "  %-6s ⚠️ 有未处理写入: %s（基线未推进）\n" "" "$pending"
  else
    printf "  %-6s ✅ 无未处理写入\n" ""
  fi
fi

# ---- 参考：最近 .md 动作（旁证，不能证明监视器在跑） ----
last=$(ls -t "$DIR"/*.md 2>/dev/null | head -1)
if [ -n "$last" ]; then
  printf "  %-6s （参考）最近 .md 动作: %s  %s\n" "" "$(basename "$last")" "$(stat -f '%Sm' -t '%H:%M:%S' "$last" 2>/dev/null)"
fi

echo
echo "说明：心跳只有在双方都写时才有意义。缺一方 → 该方在线与否仍不可判。"

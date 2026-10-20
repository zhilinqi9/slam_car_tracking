#!/usr/bin/env bash
# 清理垃圾文件。每次会话结束、提交 git 之前运行（/session-end 会自动调用）。
#   ./tools/clean.sh          删除已知垃圾 + 列出需要人工决定的未跟踪文件
#   ./tools/clean.sh --deep   另外删除 catkin 编译产物（build/devel/logs），并清理 ~/.ros/log
#
# 只删除下面明确列出的类型；不认识的文件只报告、不删除。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DEEP=0
[[ "${1:-}" == "--deep" ]] && DEEP=1

removed=0
del() {  # del <find 条件...>：删除匹配项并计数（不进入 .git、refs、data/maps、data/paths）
  while IFS= read -r -d '' f; do
    rm -rf -- "$f"; echo "  删除 $f"; removed=$((removed + 1))
  done < <(find . \( -path ./.git -o -path ./refs -o -path ./data/maps -o -path ./data/paths \) -prune -o \( "$@" \) -print0)
}

echo "== 缓存与编辑器临时文件"
del -type d -name __pycache__
del -type d -name .pytest_cache
del -type f \( -name '*.pyc' -o -name '*~' -o -name '*.swp' -o -name '*.swo' -o -name '*.orig' -o -name '*.rej' \)
del -type f \( -name .DS_Store -o -name Thumbs.db -o -name 'core' -o -name 'core.[0-9]*' \)

echo "== 中断的录包（.bag.active 无法直接回放，需要的话先 rosbag reindex）"
del -type f -name '*.bag.active'

if [[ $DEEP -eq 1 ]]; then
  echo "== 编译产物（--deep）"
  for d in ros_ws/build ros_ws/devel ros_ws/install ros_ws/logs ros_ws/.catkin_tools; do
    [[ -e $d ]] && { rm -rf -- "$d"; echo "  删除 $d"; removed=$((removed + 1)); }
  done
  command -v rosclean >/dev/null && { echo "== ~/.ros/log"; rosclean purge -y; }
fi

echo "== 已删除 $removed 项"

# 未跟踪且未被 .gitignore 忽略的文件：要么提交，要么删除，不能一直悬着
untracked=$(git ls-files --others --exclude-standard)
if [[ -n "$untracked" ]]; then
  echo "== 以下未跟踪文件需要决定：提交，或者删除 / 加入 .gitignore"
  echo "$untracked" | sed 's/^/  ? /'
fi

# Codex 用的 AGENTS.md、.codex/agents/ 由 CLAUDE.md、.claude/agents/ 生成，两边必须一致
py=""
for cand in python3 python; do  # Windows 上的 python3 可能是应用商店占位程序，要确认真能运行
  if command -v "$cand" >/dev/null && "$cand" -c 'import sys' >/dev/null 2>&1; then py=$cand; break; fi
done
if [[ -n "$py" ]]; then
  if ! "$py" tools/sync_codex.py --check; then
    echo "== Codex 规则和 Claude 规则不一致：运行 python3 tools/sync_codex.py 重新生成后再提交"
  fi
else
  echo "== 没有 python3，跳过 Codex 规则一致性检查"
fi

# 体积提醒：bag 不入库，但会占满 Jetson 磁盘
if [[ -d data/bags ]]; then
  echo "== data/bags 占用 $(du -sh data/bags | cut -f1)（超过 10G 时把旧 bag 拷到 PC 再删除）"
fi

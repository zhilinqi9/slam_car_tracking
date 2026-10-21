#!/usr/bin/env bash
# 按 thirdparty/repos.yaml 拉取第三方源码、打补丁、编译到 thirdparty_ws/（不入库）
#   ./tools/setup_thirdparty.sh            等同于 all
#   ./tools/setup_thirdparty.sh all        fetch → patch → sdk → build
#   ./tools/setup_thirdparty.sh fetch      拉取并切到 repos.yaml 固定的 commit（含子模块），会先撤掉已打的补丁
#   ./tools/setup_thirdparty.sh patch      撤掉旧补丁，重新打 thirdparty/patches/ 下的补丁（可重复执行）
#   ./tools/setup_thirdparty.sh sdk        编译 Livox-SDK2；/usr/local 已有就跳过安装，加 --force 才重装（需要 sudo）
#   ./tools/setup_thirdparty.sh build      catkin 编译 thirdparty_ws
#   ./tools/setup_thirdparty.sh status     各仓库 commit 是否和 repos.yaml 一致、补丁是否已打上
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WS="$REPO/thirdparty_ws"
REPOS_YAML="$REPO/thirdparty/repos.yaml"
PATCHES="$REPO/thirdparty/patches"
SDK_DIR="$WS/sdk/Livox-SDK2"
SDK_LIB=/usr/local/lib/liblivox_lidar_sdk_static.a   # livox_ros_driver2 的 CMakeLists 写死从这里找
SDK_MARK=/usr/local/share/livox_sdk2_commit          # 本脚本安装时写入的 commit；库文件本身没有版本号

need() { command -v "$1" >/dev/null || { echo "缺少 $1：$2"; exit 1; }; }

# 输出 repos.yaml 中每个仓库的 "路径 commit"
list_repos() {
  python3 - "$REPOS_YAML" <<'EOF'
import sys, yaml
for path, r in yaml.safe_load(open(sys.argv[1]))["repositories"].items():
    print(path, r["version"])
EOF
}

patches_of() { ls "$PATCHES/$1"/*.patch 2>/dev/null || true; }

# 撤掉补丁：按倒序反向应用已打上的补丁（补丁新建的文件也一并删掉）。
# 撤完还有改动，说明有人手工改过第三方源码，停下来让人处理，不悄悄丢掉
restore() {
  local dir="$1" name="$2" p
  for p in $(patches_of "$name" | sort -r); do
    git -C "$dir" apply --reverse --check "$p" 2>/dev/null && git -C "$dir" apply --reverse --whitespace=nowarn "$p"
  done
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]]; then
    echo "✘ $dir 有补丁以外的改动（手工修改？）。要保留就做成补丁放进 thirdparty/patches/$name/，不要就 git -C $dir checkout -- . 后重跑"
    git -C "$dir" status --short --untracked-files=no
    exit 1
  fi
}

# 先把清单读进变量：repos.yaml 解析失败时 set -e 能直接退出，不会拿空列表继续跑
read_repos() { REPOS="$(list_repos)"; [[ -n "$REPOS" ]] || { echo "repos.yaml 里没有仓库"; exit 1; }; }

do_fetch() {
  need vcs "sudo apt install -y python3-vcstool"
  mkdir -p "$WS"
  read_repos
  while read -r path _; do
    [[ -d "$WS/$path/.git" ]] && restore "$WS/$path" "$(basename "$path")"
  done <<< "$REPOS"
  vcs import --recursive --input "$REPOS_YAML" "$WS"
  # vcs import 只在克隆时递归子模块；已存在的仓库切换 commit 后要手动同步
  while read -r path _; do
    git -C "$WS/$path" submodule update --init --recursive -q
  done <<< "$REPOS"
}

do_patch() {
  read_repos
  while read -r path _; do
    local name; name="$(basename "$path")"
    local dir="$WS/$path"
    [[ -d "$dir/.git" ]] || { echo "$path 未拉取，先运行 fetch"; exit 1; }
    restore "$dir" "$name"
    for p in $(patches_of "$name"); do
      git -C "$dir" apply --whitespace=nowarn "$p"
      echo "已打补丁 $name/$(basename "$p")"
    done
  done <<< "$REPOS"
  # 驱动的 ROS1 编译方式照搬它的 build.sh：用 package_ROS1.xml 作为 package.xml（build.sh 本身会删工作空间，不能直接调用）
  cp -f "$WS/src/livox_ros_driver2/package_ROS1.xml" "$WS/src/livox_ros_driver2/package.xml"
}

do_sdk() {
  [[ -d "$SDK_DIR/.git" ]] || { echo "Livox-SDK2 未拉取，先运行 fetch"; exit 1; }
  local want; want="$(git -C "$SDK_DIR" rev-parse HEAD)"
  if [[ -f "$SDK_LIB" && "${1:-}" != "--force" ]]; then
    if [[ -f "$SDK_MARK" && "$(cat "$SDK_MARK")" == "$want" ]]; then
      echo "Livox-SDK2 @ ${want:0:7} 已安装，跳过"
    else
      echo "! $SDK_LIB 已存在，但不是本脚本按当前 commit 安装的（标记 $SDK_MARK：$(cat "$SDK_MARK" 2>/dev/null || echo 无)）。跳过；要按 repos.yaml 重装就加 --force"
    fi
    return
  fi
  cmake -S "$SDK_DIR" -B "$SDK_DIR/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$SDK_DIR/build" -j"$(nproc)"
  echo "安装到 /usr/local 需要 sudo："
  sudo cmake --install "$SDK_DIR/build"
  echo "$want" | sudo tee "$SDK_MARK" >/dev/null
}

do_build() {
  need catkin "sudo apt install -y python3-catkin-tools"
  [[ -f /opt/ros/noetic/setup.bash ]] || { echo "没有 /opt/ros/noetic"; exit 1; }
  set +u; source /opt/ros/noetic/setup.bash; set -u   # 本脚本是 bash，和用户的 zsh 环境无关
  [[ -f "$SDK_LIB" ]] || { echo "缺少 $SDK_LIB，先运行 sdk"; exit 1; }
  cd "$WS"
  [[ -d .catkin_tools ]] || catkin init
  catkin config --extend /opt/ros/noetic \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DROS_EDITION=ROS1
  catkin build
  cat <<EOF

thirdparty_ws 编译完成。ros_ws 要叠加在它上面（只需一次；改 extend 后必须 clean）：
  cd $REPO/ros_ws && catkin config --extend $WS/devel && catkin clean -y && catkin build
EOF
}

do_status() {
  local rc=0
  read_repos
  while read -r path want; do
    local name; name="$(basename "$path")"
    local dir="$WS/$path"
    if [[ ! -d "$dir/.git" ]]; then echo "✘ $path 未拉取"; rc=1; continue; fi
    local head; head="$(git -C "$dir" rev-parse HEAD)"
    if [[ "$head" == "$want" ]]; then echo "✔ $path @ ${head:0:7}"; else echo "✘ $path @ ${head:0:7}，应为 ${want:0:7}"; rc=1; fi
    for p in $(patches_of "$name"); do
      if git -C "$dir" apply --reverse --check "$p" 2>/dev/null; then
        echo "    ✔ 补丁 $(basename "$p")"
      else
        echo "    ✘ 补丁 $(basename "$p") 未打上"; rc=1
      fi
    done
    # 精确比较：HEAD + 全部补丁 应该正好等于工作区（已跟踪文件），用临时 index，不碰仓库自己的 index
    local tmp; tmp="$(mktemp -d)"
    local want_tree have_tree
    want_tree="$(cd "$dir" && export GIT_INDEX_FILE="$tmp/want" && git read-tree HEAD && \
      for p in $(patches_of "$name"); do git apply --cached --whitespace=nowarn "$p"; done && git write-tree)"
    have_tree="$(cd "$dir" && export GIT_INDEX_FILE="$tmp/have" && git read-tree HEAD && git add -u && git write-tree)"
    rm -rf "$tmp"
    [[ "$want_tree" == "$have_tree" ]] || { echo "    ✘ 工作区不等于 HEAD + 补丁（有手工修改？git -C $dir diff 查看）"; rc=1; }
  done <<< "$REPOS"
  if [[ -f "$SDK_MARK" ]]; then
    [[ "$(cat "$SDK_MARK")" == "$(git -C "$SDK_DIR" rev-parse HEAD 2>/dev/null)" ]] && echo "✔ /usr/local 的 SDK2 是按当前 commit 安装的" || { echo "✘ /usr/local 的 SDK2 是 $(cut -c1-7 "$SDK_MARK")，和 repos.yaml 不一致"; rc=1; }
  else
    echo "! /usr/local 的 SDK2 不是本脚本安装的，版本未知（Jetson 上现有的这份来自 ~/Lib/Livox-SDK2，git describe = v1.2.5）"
  fi
  return $rc
}

case "${1:-all}" in
  fetch)  do_fetch ;;
  patch)  do_patch ;;
  sdk)    do_sdk "${2:-}" ;;
  build)  do_build ;;
  status) do_status ;;
  all)    do_fetch; do_patch; do_sdk "${2:-}"; do_build; do_status ;;
  *)      echo "用法: $0 {all|fetch|patch|sdk [--force]|build|status}"; exit 1 ;;
esac

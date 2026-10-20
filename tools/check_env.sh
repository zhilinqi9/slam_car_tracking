#!/usr/bin/env bash
# 一键体检：系统版本 / ROS / 第三方 / CAN / 雷达网络与对时 / 传感器设备 / 磁盘。只读，不改任何东西。
# 用法：./tools/check_env.sh            雷达 IP 默认从 LIVOX_IP 环境变量读取，例如 LIVOX_IP=192.168.1.1xx ./tools/check_env.sh
set -u
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_L4T="R35 (release), REVISION: 6.1"   # JetPack 5.1.5，2026-10-20 实测
MIN_FREE_GB=100                                # 原始点云 bag 每小时约 10–20 GB（待实测）

info "系统"
if [[ -f /etc/nv_tegra_release ]]; then
  l4t=$(head -1 /etc/nv_tegra_release)
  [[ "$l4t" == *"$EXPECTED_L4T"* ]] && ok "L4T: $l4t" || bad "L4T 不是预期的 R35.6.1：$l4t"
else
  bad "不是 Jetson（或缺 /etc/nv_tegra_release）"
fi
ok "$(lsb_release -ds 2>/dev/null || cat /etc/os-release | head -1)"
if command -v nvpmodel >/dev/null; then
  mode=$(sudo -n nvpmodel -q 2>/dev/null | head -1)
  ok "功耗模式: ${mode:-需 sudo 查看}"
fi

info "ROS"
[[ -f /opt/ros/noetic/setup.bash ]] && ok "ROS Noetic 已安装" || bad "未找到 /opt/ros/noetic"
command -v catkin >/dev/null && ok "catkin_tools $(catkin --version 2>/dev/null | head -1)" || bad "缺 python3-catkin-tools"
command -v vcs >/dev/null && ok "vcstool" || bad "缺 python3-vcstool（setup_thirdparty.sh 需要）"
for p in map_server move_base pcl_ros depthai_ros_driver; do
  [[ -d /opt/ros/noetic/share/$p ]] && ok "$p" || bad "$p 未安装"
done

info "第三方（thirdparty_ws）"
# 库文件名按 Livox-SDK2 的 CMake 安装规则写的，P0 安装后核实
ls /usr/local/lib/liblivox_lidar_sdk_shared.so* >/dev/null 2>&1 && ok "Livox-SDK2" || bad "Livox-SDK2 未安装（/usr/local/lib 下没有 liblivox_lidar_sdk_shared）"
for p in livox_ros_driver2 fast_lio; do
  if [[ -d "$REPO/thirdparty_ws/src" ]] && find "$REPO/thirdparty_ws/src" -maxdepth 3 \( -name package.xml -o -name package_ROS1.xml \) -exec grep -l "<name>$p</name>" {} + 2>/dev/null | grep -q .; then
    ok "$p 源码已拉取"
  else
    bad "$p 未拉取或没有 package.xml（运行 tools/setup_thirdparty.sh）"
  fi
done
[[ -f "$REPO/thirdparty_ws/devel/setup.zsh" ]] && ok "thirdparty_ws 已编译" || bad "thirdparty_ws 未编译"

info "CAN"
command -v candump >/dev/null && ok "can-utils" || bad "缺 can-utils"
if ip link show can0 >/dev/null 2>&1; then
  state=$(ip -details link show can0 | grep -o 'state [A-Z-]*' | head -1)
  bitrate=$(ip -details link show can0 | grep -o 'bitrate [0-9]*' | head -1)
  [[ "$bitrate" == "bitrate 500000" ]] && ok "can0 存在（$state，$bitrate）" || bad "can0 存在（$state），但波特率不是 500000：${bitrate:-未知}"
else
  bad "can0 不存在（PCAN-USB 未插或 peak_usb 未加载）"
fi

info "雷达网络与对时（Mid-360）"
eth_ips=$(ip -4 -o addr show 2>/dev/null | awk '$2 !~ /^(lo|can|wl|docker|br-|veth|tun|tailscale|zt|l4tbr|rndis|usb)/ {print $2" "$4}')
[[ -n "$eth_ips" ]] && ok "有线网口 IP：$(echo "$eth_ips" | tr '\n' ' ')" || bad "没有配置了 IPv4 的有线网口"
if [[ -n "${LIVOX_IP:-}" ]]; then
  # 家用路由器常常也是 192.168.1.0/24：要确认到雷达的包是从有线网口直连出去的，不是经过网关或 Wi-Fi
  route=$(ip -o route get "$LIVOX_IP" 2>/dev/null)
  dev=$(echo "$route" | grep -o 'dev [^ ]*' | awk '{print $2}')
  if [[ -z "$route" ]]; then
    bad "没有到雷达 $LIVOX_IP 的路由"
  elif [[ "$route" == *" via "* || "$dev" == wl* ]]; then
    bad "到雷达 $LIVOX_IP 的路由不是有线直连：$route"
  else
    ok "到雷达 $LIVOX_IP 的路由：有线直连（$dev）"
  fi
  ping -c 2 -W 1 "$LIVOX_IP" >/dev/null 2>&1 && ok "能 ping 通雷达 $LIVOX_IP" || bad "ping 不通雷达 $LIVOX_IP（供电、网线、网段）"
else
  warn "未设置 LIVOX_IP，跳过路由和 ping 检查（P0 验收时必须带上：LIVOX_IP=<雷达 IP> ./tools/check_env.sh）"
fi
command -v ptp4l >/dev/null && ok "linuxptp（ptp4l）" || bad "缺 linuxptp（雷达对时需要）"
pgrep -x ptp4l >/dev/null && ok "ptp4l 正在运行" || warn "ptp4l 未运行（P2 对时之前可以忽略）"

info "设备"
lsusb 2>/dev/null | grep -qi '03e7' && ok "OAK 相机（Movidius 03e7）" || bad "未检测到 OAK"

# data/bags 可能是指向外接 SSD 的软链接；存在时测它所在的盘
data_dir="$REPO/data"
[[ -e "$REPO/data/bags" ]] && data_dir="$REPO/data/bags"
info "磁盘（bag 存放：$data_dir）"
free_gb=$(df -BG --output=avail "$data_dir" 2>/dev/null | tail -1 | tr -dc '0-9')
if [[ -n "$free_gb" ]]; then
  (( free_gb >= MIN_FREE_GB )) && ok "剩余 ${free_gb} GB" || bad "剩余 ${free_gb} GB，少于 ${MIN_FREE_GB} GB"
else
  bad "无法读取 $data_dir 所在磁盘的剩余空间"
fi

info "Claude Code"
command -v claude >/dev/null && ok "claude $(claude --version 2>/dev/null)" || bad "未安装 Claude Code"

#!/usr/bin/env bash
# 一键体检：系统版本 / ROS / 工具链 / CAN / 传感器设备。只读，不改任何东西。
# 用法：./tools/check_env.sh
set -u
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }

info "系统"
[[ -f /etc/nv_tegra_release ]] && ok "L4T: $(head -1 /etc/nv_tegra_release)" || bad "不是 Jetson（或缺 /etc/nv_tegra_release）"
ok "$(lsb_release -ds 2>/dev/null || cat /etc/os-release | head -1)"
command -v nvpmodel >/dev/null && ok "功耗模式: $(sudo -n nvpmodel -q 2>/dev/null | head -1 || echo '需 sudo 查看')"

info "ROS"
[[ -f /opt/ros/noetic/setup.bash ]] && ok "ROS Noetic 已安装" || bad "未找到 /opt/ros/noetic"
command -v catkin >/dev/null && ok "catkin_tools $(catkin --version 2>/dev/null | head -1)" || bad "缺 python3-catkin-tools"
for p in robot_localization slam_toolbox amcl map_server move_base rplidar_ros depthai_ros_driver depthai_examples; do
  [[ -d /opt/ros/noetic/share/$p ]] && ok "$p" || bad "$p 未安装"
done

info "CAN"
command -v candump >/dev/null && ok "can-utils" || bad "缺 can-utils"
if ip link show can0 >/dev/null 2>&1; then
  state=$(ip -details link show can0 | grep -o 'state [A-Z-]*' | head -1)
  ok "can0 存在（$state）"
else
  bad "can0 不存在（PCAN-USB 未插或 peak_usb 未加载）"
fi

info "设备"
lsusb 2>/dev/null | grep -qi '03e7' && ok "OAK 相机（Movidius 03e7）" || bad "未检测到 OAK"
lsusb -t 2>/dev/null | grep -q '5000M' && ok "存在 USB3 设备（确认 OAK 跑在 5000M 上）" || bad "没有 USB3 设备，OAK 可能降级为 USB2"
ls /dev/rplidar >/dev/null 2>&1 && ok "/dev/rplidar" || bad "/dev/rplidar 不存在（雷达未接或 udev 规则未装）"

info "Claude Code"
command -v claude >/dev/null && ok "claude $(claude --version 2>/dev/null)" || bad "未安装 Claude Code"

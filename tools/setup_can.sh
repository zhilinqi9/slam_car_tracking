#!/usr/bin/env bash
# 配置 FW-mini-pro 使用的 CAN 接口（PEAK PCAN-USB，500 kbps）
#   ./tools/setup_can.sh up        立即拉起（重启后失效）
#   ./tools/setup_can.sh install   写入 systemd-networkd，开机自动拉起
#   ./tools/setup_can.sh status    查看状态 + 抓 20 帧
set -euo pipefail

IFACE="${CAN_IFACE:-can0}"
BITRATE=500000

need_root() { [[ $EUID -eq 0 ]] || { echo "需要 sudo：sudo $0 $*"; exit 1; }; }

case "${1:-status}" in
  up)
    need_root "$@"
    modprobe peak_usb 2>/dev/null || true
    ip link set "$IFACE" down 2>/dev/null || true
    ip link set "$IFACE" type can bitrate "$BITRATE" restart-ms 100
    ip link set "$IFACE" up
    ip -details link show "$IFACE"
    ;;
  install)
    need_root "$@"
    echo peak_usb > /etc/modules-load.d/peak_usb.conf
    cat > /etc/systemd/network/80-${IFACE}.network <<EOF
[Match]
Name=${IFACE}

[CAN]
BitRate=500K
RestartSec=100ms
EOF
    systemctl enable --now systemd-networkd
    systemctl restart systemd-networkd
    sleep 1
    ip -details link show "$IFACE"
    ;;
  status)
    ip -details -statistics link show "$IFACE" || { echo "$IFACE 不存在：检查 PCAN-USB 是否插好、lsmod | grep peak_usb"; exit 1; }
    command -v candump >/dev/null || { echo "缺少 can-utils：sudo apt install can-utils"; exit 1; }
    echo "--- 抓 20 帧（底盘上电时应看到 18C4D1EF 等反馈帧）"
    timeout 3 candump -n 20 "$IFACE" || echo "3 秒内没有收到帧：检查底盘电源、CAN-H/CAN-L 接线（顶部电气板 13/14 脚）、波特率"
    ;;
  *)
    echo "用法: $0 {up|install|status}"; exit 1 ;;
esac

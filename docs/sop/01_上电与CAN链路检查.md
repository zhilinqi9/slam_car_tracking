# SOP 01 上电与 CAN 链路检查

> 依据：手册 3.1 / 4.3–4.5 节，以及 v1 实测经验。P0 阶段上车逐条验证，验证后把本行改为"已于 YYYY-MM-DD 验证（commit xxx）"。

## 1. 接线
- PCAN-USB 接 Jetson 的 USB 口；CAN 线接底盘**顶部电气板**：13 脚 = CAN-H，14 脚 = CAN-L
- 如果总线上只有底盘和 PCAN 两个节点，确认终端电阻（120 Ω）配置正确

## 2. 上电顺序
1. 遥控器开机，拨杆全部向上（默认位置）
2. 按下底盘启动按钮，确认急停已释放
3. Jetson 上电

## 3. 拉起 CAN 并确认有反馈

```bash
sudo ./tools/setup_can.sh up      # 首次使用；之后用 install 设成开机自启
./tools/setup_can.sh status
```

**期望看到**：`can0` 的状态为 `ERROR-ACTIVE`，并能抓到以下 ID（candump 显示 29 位 ID）：

| ID | 内容 | 周期 |
|---|---|---|
| `18C4D1EF` | ctrl_fb（档位 / vx / wz / vy） | 10 ms |
| `18C4D6EF`–`18C4D9EF` | 四轮速度和脉冲 | 10 ms |
| `18C4DAEF` | io_fb（急停、遥控、防撞条） | 50 ms |
| `18C4E1EF` / `18C4E2EF` | 电池 / SOC | 100 ms |
| `18C4EAEF` | 故障 | 100 ms |

**不对时**：
- 一帧都没有 → 检查底盘电源、接线、波特率（必须 500 k），以及 `ip -s link show can0` 里的错误计数
- 状态是 `BUS-OFF` 或 `ERROR-PASSIVE` → CAN-H/L 可能接反，或缺终端电阻
- 测量频率：`candump -td can0,18C4D1EF:1FFFFFFF -n 100`，帧间隔应约为 0.010 s

## 4. 切换到指令控制模式
- 遥控器 **SWA 拨杆向下** = 指令控制模式（向上 = 遥控模式）
- 在 `io_fb` 里确认：Byte5 bit1（遥控器控制状态）= 0。P1 完成后直接看 `rostopic echo /chassis/state`

## 5. 底层控制冒烟测试（只在**架空**状态下做，需人工执行）

> 这一步用于 P1 前确认"能发能动"。P1 之后一律通过 `fw_chassis_node` 控制，不再手工发帧。

手册例 1 的帧（4T4D 档，0.5 m/s，-25°/s）必须以 10 ms 间隔连续发送，并且心跳要变化。单发一帧车不会动，这属于正常现象。手工测试建议用 P1 的驱动节点来做，不要用 cansend 循环。

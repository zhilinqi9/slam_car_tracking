# 室内建图与示教路径复现小车（v2）

FW-mini-pro 四转四驱线控底盘 + Jetson Orin NX + Livox Mid-360（3D 激光雷达，倒装）+ OAK-D Pro。
**建图 → 遥控示教一条路线 → 小车在地图上定位并反复沿这条路线行驶，遇到障碍停车，障碍清除后继续。**

> v1（RTAB-Map 纯视觉方案）的代码和说明已移出工作树，用 git tag [`v1`](https://github.com/zhilinqi9/slam_car_tracking/tree/v1) 保留，问题分析见 [项目评估报告](docs/00_项目评估报告.md)。

## 技术栈
ROS1 Noetic · JetPack 5.1.5（L4T R35.6.1）· FAST-LIO2 激光惯性里程计 · 离线闭环建图 · 先验地图 GICP 定位（small_gicp）· 自研 Regulated Pure Pursuit 路径跟随 · SocketCAN

## 文档
| 文档 | 内容 |
|---|---|
| [00 项目评估报告](docs/00_项目评估报告.md) | v1 的 27 条问题及根因 |
| [01 技术路线与里程碑](docs/01_技术路线与里程碑.md) | 架构、包划分、P0–P5 各阶段及验收门槛 |
| [02 Claude Code 工作流](docs/02_ClaudeCode工作流.md) | 多 Agent 协作方式与每次会话的标准流程 |
| [CAN 协议速查](docs/hardware/FW-mini-pro_CAN协议速查.md) | 底盘协议与参数 |
| [Mid-360 速查](docs/hardware/Livox_Mid-360速查.md) | 雷达网络、视场、对时、外参 |
| [操作说明 SOP](docs/sop/README.md) | 上电、标定、建图、示教、运行 |
| [工作日志](docs/worklog/) | 每次会话的记录 |

## 快速开始（Jetson）
```bash
git clone https://github.com/zhilinqi9/slam_car_tracking.git ~/slam_car_tracking
cd ~/slam_car_tracking
./tools/check_env.sh                 # 环境体检
sudo ./tools/setup_can.sh install    # can0 开机自启（500 kbps）
cd ros_ws && catkin build && catkin test
```

## 目录
```
ros_ws/src/   fw_chassis（底盘驱动）· yhs_can_msgs（厂家消息）· 后续：fw_description / fw_localization / fw_bringup / fw_navigation / fw_tools
thirdparty/   第三方源码清单（固定 commit）与补丁；编译到 thirdparty_ws/（不入库）
docs/         评估报告、路线图、工作流、硬件资料、SOP、工作日志
data/         maps/、paths/（入库）· bags/、reports/（不入库）
tools/        check_env.sh（体检）· setup_can.sh（CAN）· clean.sh（清理垃圾，每次提交前运行）
refs/         厂家手册 PDF（本地，不入库）
```

## 进度
见 [技术路线与里程碑](docs/01_技术路线与里程碑.md) 的勾选状态，以及最新一篇[工作日志](docs/worklog/)。

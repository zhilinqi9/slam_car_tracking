# CLAUDE.md — 室内建图与示教路径复现小车

所有对话、文档、注释一律用**中文**；代码标识符用英文。

## 项目目标
FW-mini-pro 线控底盘 + Jetson Orin NX：先建 3D 点云地图（同时生成 2D 栅格），再遥控示教一条路线，之后小车在地图上定位并**反复沿这条路线行驶**，遇到障碍停车，障碍清除后继续。
路线图与验收标准见 `docs/01_技术路线与里程碑.md`；当前处于哪个阶段，看最新一篇 `docs/worklog/*.md`。

## 平台（不要擅自更改）
- Jetson Orin NX，JetPack 5.1.5 / L4T R35.6.1（2026-10-20 实测），Ubuntu 20.04，**ROS1 Noetic**，`catkin build`（catkin_tools）
- 底盘：FW-mini-pro **四转四驱（4T4D）**，**不是差速底盘，也不是全向底盘**；PEAK PCAN-USB → `can0` @ 500 kbps
- 传感器：**Livox Mid-360，倒装**（3D 激光 + 内置 IMU，以太网；主定位与近场避障）、OAK-D Pro（深度相机用于 P5 补充避障）
- 用户 shell 是 zsh：source `devel/setup.zsh`，不要用 `.bash`

## 底盘硬事实（来源：docs/hardware/FW-mini-pro_CAN协议速查.md）
- ctrl_cmd 档位：**0 = disable，1 = 驻车**，2 = 空档，**6 = 4T4D（只有 vx + wz 有效）**，8 = 横移（只有 vx + vy 有效）
- 角速度在 CAN 上的单位是 **0.01 °/s**，手册规定俯视逆时针为正；实车符号以 P1 标定出的 `angular_sign` 参数为准
- 控制帧必须以 10–50 ms 的周期连续发送，带 alive 计数和 BCC 校验
- 遥控器 SWA 拨杆优先级最高：向上 = 遥控模式，此时 CAN 指令无效

## 雷达硬事实（来源：docs/hardware/Livox_Mid-360速查.md，标"待核实"的项不能当作事实使用）
- 以太网接口，静态 IP；驱动是 livox_ros_driver2 + Livox-SDK2，话题 `/livox/lidar`（CustomMsg）、`/livox/imu`
- **倒装**：URDF 里 `livox_frame` 的 roll = π；FAST-LIO 的 body 坐标系 = 雷达内置 IMU 坐标系（`livox_imu`）
- 雷达时间戳必须通过 PTP 和系统时间对齐，否则 TF 和 bag 分析会对不上

## 架构硬规则（违反任何一条都视为 bug）
1. **每个 TF 只有一个发布者**：`map→odom` 只由 `map_localizer` 发布（只通过 localization.launch 启动，teach/repeat 必须 include 它，不得自行启动）；`odom→base_footprint` 只由 `lio_odom_bridge` 发布（FAST-LIO 自带的 TF 广播必须关掉）；其余来自 robot_state_publisher（URDF）。不要再写零散的 `static_transform_publisher`，也不要再引入 EKF、AMCL 来发布这些 TF。
2. ROS 接口一律使用 SI 单位 + REP-103（rad/s，逆时针为正）。°/s 转换和符号修正**只在 `fw_chassis` 内部**做一次。
3. **只有 `safety_guard` 能发布 `/cmd_vel`**。控制器输出到 `/cmd_vel_nav`、`/cmd_vel_move_base` 等话题。
4. 规划器和控制器必须按**非全向**模型配置（不能设 `holonomic_robot: true`，`vy` 必须为 0）。
5. costmap 使用 `plugins:` 时，每个层的参数都要放在**该层自己的命名空间**下（如 `obstacle_layer/observation_sources`）。
6. 协议、数学、积分这类逻辑写成**不依赖 ROS 的纯函数**并配单元测试；ROS 节点只做一层薄封装。
7. 第三方源码（Livox-SDK2、livox_ros_driver2、FAST_LIO、small_gicp 等）**不放进 `ros_ws/src`**：在 `thirdparty/repos.yaml` 里固定 commit，我们的修改存成 `thirdparty/patches/` 下的补丁，由 `tools/setup_thirdparty.sh` 编译到 `thirdparty_ws/`（不入库）。
8. 下游节点（跟随器、`safety_guard`）只要看到 `/localization/status` 不是 `OK` 就必须停车，超过 0.5 s 没收到 status 等同于 `LOST`；`path_recorder` 在不是 `OK` 时暂停记录。
9. 离线回放 bag 重跑算法时，不能回放 bag 里的 `/tf`（规则见 docs/01 第 1.2 节）。

## 目录
```
ros_ws/src/          catkin 工作空间（v2 代码都在这里）
  fw_chassis/        底盘驱动（protocol.hpp 已完成，15 个测试）
  fw_localization/   lio_odom_bridge、map_localizer（待建，P2–P3）
  yhs_can_msgs/      厂家消息，仅用于调试对照
docs/
  00_项目评估报告.md    v1 问题清单（新代码不要重复这些错误）
  01_技术路线与里程碑.md  架构 + 阶段 + 验收门槛
  02_ClaudeCode工作流.md
  hardware/          协议速查等硬件资料
  sop/               操作说明（累积型：现在该怎么做）
  worklog/           工作日志（每次会话一篇：当天做了什么）
data/maps|paths/     地图、路线（入库）；data/bags/ 不入库
thirdparty/          repos.yaml（固定 commit）+ patches/（待建，P0）；编译产物在 thirdparty_ws/（不入库）
tools/               setup_can.sh、check_env.sh、clean.sh；setup_thirdparty.sh（待建，P0）
refs/                厂家手册 PDF（本地参考，不入库）
```
- v1 代码不在工作树里，用 tag `v1` 保留：`git show v1:FW-mini-pro-ros1/src/<文件>`。只作参考，不要从中复制 bug。
- `refs/` 里的 PDF 可以读，但**不要提交**；需要长期使用的内容整理成 `docs/hardware/` 下的 markdown。
- 旧文件夹 `E:\SLAM建图及小车循迹` 只是用户个人材料和厂家资料的存档，**不要在那里工作，也不要读写其中的个人文件**。

## 常用命令
```bash
cd ~/slam_car_tracking/ros_ws
catkin build                              # 全量编译
catkin build fw_chassis --no-deps         # 只编译单个包
catkin test fw_chassis                    # 单元测试
source devel/setup.zsh
./tools/check_env.sh                      # 环境体检（只读）
./tools/setup_can.sh status               # CAN 状态 + 抓 20 帧
```

## 安全（机器人会动，最高优先级）
- **不要自己执行任何会让车动的命令**：`rostopic pub` 到 `/cmd_vel*` 或 `/ctrl_cmd`、`cansend`、启动 repeat / teleop / navigation 类 launch。要先把命令写出来，说明车需要处于什么状态（架空 / 场地清空 / 遥控器在手），等用户确认后再执行
- 新的运动代码必须先在架空状态下测试；默认限速 vx ≤ 0.3 m/s，wz ≤ 0.5 rad/s
- 只读类操作（`rostopic echo/hz/list`、`candump`、`rosbag info`、编译、测试）可以直接执行

## 工作方式
- 会话开始先运行 `/session-start`，结束前运行 `/session-end`。**每次会话必须留下一篇工作日志**；如果操作流程变了，同步更新 SOP
- 非小改动先进入 Plan 模式出方案，用户确认后再写代码
- **代码是唯一事实来源**。工作日志里只写 commit hash、实测数据、bag 文件名和结论，不贴"示意代码"（v1 的日志和代码对不上，这个问题要避免）
- 结论必须有证据：测试输出、`rostopic hz` 结果、bag 指标。没有在车上验证过的，写"未验证"
- 调参必须有量化对比（改之前和改之后同一指标的数值），用 `fw_tools` 里的脚本从 bag 里算

## 收尾：每完成一项工作都要清理并提交（用户的长期要求）
1. `./tools/clean.sh` 清理垃圾；它列出的未跟踪文件逐个决定：有用的提交，没用的删除或加入 `.gitignore`。不允许留下来路不明的文件
2. `catkin build && catkin test` 通过（只改了文档时可以跳过）
3. 写好或更新工作日志（`/session-end` 会完成第 1–4 步）
4. `git add` → `git commit` → `git push origin <当前分支>`。不需要再问用户，但要在回复里报告 commit hash
   - 提交信息用中文，格式 `<包名>: <做了什么>`；代码和文档分开提交；末尾加 Co-Authored-By 行
   - 测试不通过时不要提交到 main：先提交到 `wip/<主题>` 分支并推送，在日志里写明原因
   - 不要用 `git push --force`、`git reset --hard`，也不要改写已推送的历史
   - 推送失败（网络、冲突）时报告给用户，不要强推

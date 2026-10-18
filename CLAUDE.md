# CLAUDE.md — 室内建图与示教路径复现小车

所有对话、文档、注释一律用**中文**；代码标识符用英文。

## 项目目标
FW-mini-pro 线控底盘 + Jetson Orin NX：先建 2D 地图，再遥控示教一条路线，之后小车在地图上定位并**反复沿这条路线行驶**，遇到障碍停车，障碍清除后继续。
路线图与验收标准见 `docs/01_技术路线与里程碑.md`；当前处于哪个阶段，看最新一篇 `docs/worklog/*.md`。

## 平台（不要擅自更改）
- Jetson Orin NX，JetPack 5.1.1 / L4T R35.3.1，Ubuntu 20.04，**ROS1 Noetic**，`catkin build`（catkin_tools）
- 底盘：FW-mini-pro **四转四驱（4T4D）**，**不是差速底盘，也不是全向底盘**；PEAK PCAN-USB → `can0` @ 500 kbps
- 传感器：2D 激光雷达（主定位）、OAK-D Pro（IMU；深度相机用于 P5 补充避障）
- 用户 shell 是 zsh：source `devel/setup.zsh`，不要用 `.bash`

## 底盘硬事实（来源：docs/hardware/FW-mini-pro_CAN协议速查.md）
- ctrl_cmd 档位：**0 = disable，1 = 驻车**，2 = 空档，**6 = 4T4D（只有 vx + wz 有效）**，8 = 横移（只有 vx + vy 有效）
- 角速度在 CAN 上的单位是 **0.01 °/s**，手册规定俯视逆时针为正；实车符号以 P1 标定出的 `angular_sign` 参数为准
- 控制帧必须以 10–50 ms 的周期连续发送，带 alive 计数和 BCC 校验
- 遥控器 SWA 拨杆优先级最高：向上 = 遥控模式，此时 CAN 指令无效

## 架构硬规则（违反任何一条都视为 bug）
1. **每个 TF 只有一个发布者**：`map→odom` 由 AMCL 或 slam_toolbox 发布（二者不能同时运行）；`odom→base_footprint` 只由 EKF 发布；其余来自 robot_state_publisher（URDF）。不要再写零散的 `static_transform_publisher`。
2. ROS 接口一律使用 SI 单位 + REP-103（rad/s，逆时针为正）。°/s 转换和符号修正**只在 `fw_chassis` 内部**做一次。
3. **只有 `safety_guard` 能发布 `/cmd_vel`**。控制器输出到 `/cmd_vel_nav`、`/cmd_vel_move_base` 等话题。
4. 规划器和控制器必须按**非全向**模型配置（不能设 `holonomic_robot: true`，`vy` 必须为 0）。
5. costmap 使用 `plugins:` 时，每个层的参数都要放在**该层自己的命名空间**下（如 `obstacle_layer/observation_sources`）。
6. 协议、数学、积分这类逻辑写成**不依赖 ROS 的纯函数**并配单元测试；ROS 节点只做一层薄封装。

## 目录
```
ros_ws/src/          catkin 工作空间（v2 代码都在这里）
  fw_chassis/        底盘驱动（protocol.hpp 已完成，15 个测试）
  yhs_can_msgs/      厂家消息，仅用于调试对照
docs/
  00_项目评估报告.md    v1 问题清单（新代码不要重复这些错误）
  01_技术路线与里程碑.md  架构 + 阶段 + 验收门槛
  02_ClaudeCode工作流.md
  hardware/          协议速查等硬件资料
  sop/               操作说明（累积型：现在该怎么做）
  worklog/           工作日志（每次会话一篇：当天做了什么）
data/maps|paths/     地图、路线（入库）；data/bags/ 不入库
tools/               setup_can.sh、check_env.sh 等脚本
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

# SLAM3_CARTracking - SLAM建图与自主导航控制系统

第十届集创赛「基于复旦微电子FMQL30TAI的多模态实验室火灾监测系统」SLAM建图与小车导航控制模块。

## 目录结构

```
SLAM3_CARTracking/
├── FW-mini-pro-ros1/          # ROS工作空间：底盘驱动 + 里程计融合 + 导航栈
│   └── src/
│       ├── fw_odom_publisher/ # 自研里程计发布 + cmd_vel转换 + EKF + move_base配置
│       │   ├── scripts/
│       │   │   ├── odom_publisher.py         # CAN反馈 -> 轮式里程计
│       │   │   └── cmd_vel_to_ctrl_cmd.py    # Twist -> CAN控制报文
│       │   ├── launch/
│       │   │   ├── fw_odom.launch            # 里程计 + EKF + 静态TF
│       │   │   └── navigation.launch         # move_base + RTAB-Map localization + cmd_vel桥接
│       │   └── config/
│       │       ├── ekf_odom.yaml             # EKF融合参数
│       │       ├── costmap_common_params.yaml
│       │       ├── global_costmap_params.yaml
│       │       ├── local_costmap_params.yaml
│       │       ├── move_base_params.yaml
│       │       └── dwa_local_planner_params.yaml
│       ├── yhs_can_control/                  # C++ CAN总线驱动节点
│       │   ├── src/yhs_can_control.cpp
│       │   └── launch/yhs_can_control.launch
│       └── yhs_can_msgs/                     # 底盘CAN消息定义（15类自定义消息）
│
└── ORB_SLAM3/                 # ORB_SLAM3 v1.0 修改版（含OAK-D适配）
    ├── src/                   # 核心SLAM源码
    ├── include/               # 头文件
    ├── Examples/              # 示例程序 + OAK-D相机YAML配置
    │   ├── RGB-D/OAK.yaml
    │   ├── RGB-D/OAKD_PRO.yaml
    │   └── Stereo/OAK-D-Pro.yaml
    ├── Thirdparty/            # DBoW2, g2o, Sophus
    ├── Vocabulary/            # ORBvoc.txt
    ├── depthai-core-main/     # Luxonis DepthAI SDK（OAK-D相机驱动）
    └── IndoorMapping/         # 稠密点云 + OctoMap子项目
```

> **关于本仓库代码范围**：仓库收录的是本项目自研的 ROS 工作空间 `FW-mini-pro-ros1/`（底盘驱动、自研里程计、EKF 融合、导航配置）。`ORB_SLAM3/` 为基于 ORB-SLAM3 v1.0 的修改版（含 OAK-D 适配），因体积较大（含 >100MB 词典与第三方依赖）未直接纳入仓库，可单独提供。

## 硬件依赖

| 组件 | 型号/说明 |
|------|-----------|
| 移动底盘 | FW-MINI-PRO 全向型智能线控底盘 |
| 视觉传感器 | OAK-D Pro 双目深度相机（RGB + Depth + IMU） |
| 计算平台 | Jetson Orin NX CLB 开发者套件（Ubuntu 20.04） |
| CAN适配器 | PEAK PCAN-USB（500 kbps） |
| 目标部署平台 | 复旦微电子 FMQL30TAI（算法移植目标） |

## 软件依赖

- ROS Noetic (Ubuntu 20.04)
- RTAB-Map ROS (`ros-noetic-rtabmap-ros`)
- robot_localization (`ros-noetic-robot-localization`)
- move_base / DWA local planner
- depthai_examples*(OAK-D相机ROS驱动，需手动编译)
- OpenCV 3.4+
- Eigen3, Pangolin, Boost

## 编译说明

### FW-mini-pro-ros1 编译

```bash
cd FW-mini-pro-ros1
catkin_make
source devel/setup.bash
```

### ORB_SLAM3 编译

```bash
cd ORB_SLAM3
chmod +x build.sh
./build.sh
```

注意：确保已安装 OpenCV 3.4（路径 `/usr/local/opencv3`）及 Pangolin。如需使用 OpenCV 4.2，可改用 `CMakeLists111.txt`。

## 系统启动流程

### 第一阶段：SLAM建图

> 各终端在执行前都需先 `source /opt/ros/noetic/setup.zsh` 与 `source ~/FW-mini-pro-ros1/devel/setup.zsh`（或对应 `.bash`）。

终端1 — 启动 OAK-D Pro 相机：
```bash
roslaunch depthai_examples stereo_inertial_node.launch \
    enableRviz:=false depth_aligned:=true mode:=depth \
    stereo_fps:=20 enableSpatialDetection:=false syncNN:=false \
    rgbScaleNumerator:=2 rgbScaleDinominator:=3 \
    subpixel:=true usb2Mode:=false confidence:=200 \
    LRchecktresh:=5 useSimulatedTime:=false \
    spatialFilter:=true temporalFilter:=true \
    decimationFilter:=2 extended:=false
```
等约 10 秒后用 `rostopic hz` 确认 `/stereo_inertial_publisher/{color/image, stereo/depth, imu}` 三路话题数据流稳定。

终端2 — 启动小车 CAN 驱动：
```bash
roslaunch yhs_can_control yhs_can_control.launch
# 用 rostopic hz /ctrl_fb 确认底盘有反馈
```

终端3 — 启动 odom 自研节点 + EKF 融合：
```bash
roslaunch fw_odom_publisher fw_odom.launch
# 用 rostopic info /odom 确认发布者为 ekf_odom_node
# 用 rosrun tf tf_echo odom base_link 确认 TF 链正常
```

终端4 — 启动 RTAB-Map（建图模式）：
```bash
roslaunch rtabmap_ros rtabmap.launch \
    rtabmap_args:="--delete_db_on_start \
        --Reg/Force3DoF true --Optimizer/Slam2D true \
        --RGBD/OptimizeMaxError 3.0 \
        --RGBD/AngularUpdate 0.05 --RGBD/LinearUpdate 0.05 \
        --Rtabmap/DetectionRate 1.0 --Mem/STMSize 30 \
        --Vis/MinInliers 25 --Vis/MaxDepth 2.0 --Vis/MinDepth 0.3 \
        --Grid/RangeMax 2.0 --Grid/RangeMin 0.3 \
        --Grid/DepthDecimation 2 --Grid/CellSize 0.05 \
        --Grid/MaxObstacleHeight 1.5 --Grid/MaxGroundHeight 0.1 \
        --Grid/NormalsSegmentation true" \
    rgb_topic:=/stereo_inertial_publisher/color/image \
    depth_topic:=/stereo_inertial_publisher/stereo/depth \
    camera_info_topic:=/stereo_inertial_publisher/color/camera_info \
    approx_sync:=true queue_size:=30 \
    frame_id:=base_link odom_topic:=/odom \
    visual_odometry:=true rtabmap_viz:=true rviz:=false \
    cloud_max_depth:=2.0 cloud_min_depth:=0.3 \
    cloud_voxel_size:=0.03 cloud_decimation:=2 \
    cloud_noise_filter_radius:=0.04 cloud_noise_filter_min_neighbors:=8 \
    cloud_subtract_filtering:=true
```

启动后 RTAB-Map ROS GUI 显示 **Loop Closure Detection**、**Odometry**、**3D Map** 三大面板，新关键帧入库时左上角实时刷新 `New ID = N`，3D Map 面板中稠密点云持续累积。

保存地图（关 RTAB-Map 前必须执行）：
```bash
rosrun map_server map_saver -f ~/maps/grid_map map:=/rtabmap/grid_map
cp ~/.ros/rtabmap.db ~/maps/site_A.db
```
随后 `Ctrl-C` 关闭终端 4，前三个终端保持运行供导航阶段复用。可用 `eog ~/maps/grid_map.pgm` 查看 2D 栅格图，用 `pcl_viewer ~/maps/cloud_map.ply` 或 CloudCompare/MeshLab 查看 3D 点云。

### 第二阶段：自主导航循迹

终端1–3 与建图阶段保持相同。

终端4 — RTAB-Map localization 重定位：
```bash
roslaunch rtabmap_ros rtabmap.launch \
    localization:=true \
    database_path:=/home/nvidia/maps/site_A.db \
    rtabmap_args:="--Reg/Force3DoF true" \
    rgb_topic:=/stereo_inertial_publisher/color/image \
    depth_topic:=/stereo_inertial_publisher/stereo/depth \
    camera_info_topic:=/stereo_inertial_publisher/color/camera_info \
    approx_sync:=true queue_size:=30 \
    frame_id:=base_link odom_topic:=/odom \
    visual_odometry:=true rtabmap_viz:=true rviz:=false
```

终端5 — move_base + cmd_vel 桥接：
```bash
roslaunch fw_odom_publisher navigation.launch
```

如需手动验证底层 CAN 链路，可用以下命令直接下发恒定速度报文：
```bash
rostopic pub -r 100 /ctrl_cmd yhs_can_msgs/ctrl_cmd \
    "{ctrl_cmd_gear: 6, ctrl_cmd_x_linear: 0.1, ctrl_cmd_y_linear: 0.0, ctrl_cmd_z_angular: 0.0}"
```

## 核心节点说明

### fw_odom_publisher（`odom_publisher.py`）
- 订阅：`/ctrl_fb`（底盘CAN反馈，含 `ctrl_fb_x_linear` 线速度与 `ctrl_fb_z_angular` 角速度）
- 发布：`/odom_raw`（标准 nav_msgs/Odometry，二维位姿 x/y/θ + 协方差矩阵）
- 积分方式：差速车二维运动学 + 中点法 (`avg_theta = θ + Δθ/2`)，`ctrl_fb` 回调内积分
- 关键参数：`angular_in_degrees`（度→弧度自动转换）、`publish_tf`（启用 EKF 时关闭，避免与 EKF 输出的 tf 重复）
- 频率：随 `/ctrl_fb` 反馈节奏，约 30 Hz

### ekf_localization_node（`robot_localization` 包）
- 订阅：`/odom_raw`（启用 vx + vyaw 通道）+ `/stereo_inertial_publisher/imu`（启用 yaw 角度通道并去除重力分量）
- 发布：`/odom`（融合里程计）+ `odom → base_link` TF（30 Hz）
- 配置：`ekf_odom.yaml`，`two_d_mode=true` 强制 2D 运动约束，`process_noise_covariance` 中 vyaw 项 0.015 提高对 IMU 的信任度

### cmd_vel_to_ctrl_cmd（`cmd_vel_to_ctrl_cmd.py`）
- 订阅：`/cmd_vel`（move_base 输出 `geometry_msgs/Twist`）
- 发布：`/ctrl_cmd`（底盘 CAN 控制报文 `yhs_can_msgs/ctrl_cmd`）
- 档位策略：线/角速度都 < 0.01 时切到 PARK（0），否则切到 FORWARD（6，本底盘前进/倒车共用 6 档）
- 安全机制：基于 `rospy.Timer(0.01s)` 的 100 Hz 心跳下发（满足底盘 ≥30 Hz 控制频率硬性要求） + 0.5 s 超时自动归零并切回 PARK

### yhs_can_control_node
- 功能：CAN 总线双向收发驱动，订阅 4 个控制话题（`/ctrl_cmd` / `/io_cmd` / `/motor_cmd` / `/steering_ctrl_cmd`），发布 15 个反馈话题
- CAN ID 模式：发送 `0x98C4D[1/2/7/8]D0`（ctrl/steering/io/motor），接收 `0x98C4D[1-D]EF`
- 校验：每帧 8 字节，第 8 字节为前 7 字节按位异或校验和

## 关键参数调优记录

| 参数 | 取值 | 说明 |
|------|------|------|
| Rtabmap/DetectionRate | 1.0 Hz | 关键帧入库节奏（USB2 受限带宽 + 稠密点云模式下取较小值） |
| Mem/STMSize | 30 | 短期记忆关键帧数 |
| RGBD/AngularUpdate / LinearUpdate | 0.05 / 0.05 | 角度/平移变化阈值，触发新关键帧 |
| RGBD/OptimizeMaxError | 3.0 | 拒绝可疑闭环避免地图扭曲 |
| Vis/MinInliers | 25 | 视觉前端最少内点数（低于此值拒绝该帧） |
| Vis/MaxDepth / MinDepth | 2.0 m / 0.3 m | OAK USB2 模式 3 m 外深度方差快速增大 |
| Reg/Force3DoF | true | SE(2) 平面配准，与 EKF `two_d_mode` 互补 |
| Grid/CellSize | 0.05 m | 占据栅格分辨率 |
| Grid/RangeMax / RangeMin | 2.0 m / 0.3 m | 2D 栅格投影距离范围 |
| Grid/DepthDecimation | 2 | 栅格构建时深度图降采样倍率 |
| Grid/MaxObstacleHeight | 1.5 m | 障碍物最大高度（超过即过滤） |
| Grid/MaxGroundHeight | 0.1 m | 地面候选最大高度阈值 |
| Grid/NormalsSegmentation | true | 基于点云法向区分地面与障碍物 |
| approx_sync / queue_size | true / 30 | OAK RGB 与 depth 时间戳近似同步 + 30 帧队列 |
| visual_odometry | true | 启用 RTAB-Map 自身的视觉里程计（EKF 仅维持 odom→base_link tf） |
| cloud_voxel_size | 0.03 m | 稠密点云体素降采样 |
| cloud_noise_filter_radius / min_neighbors | 0.04 m / 8 | 半径离群点滤波 |
| cloud_subtract_filtering | true | 关键帧间冗余点云去重 |
| max_vel_x / max_vel_theta | 0.3 m/s / 0.5 rad/s | DWA 最大前向速度与角速度 |
| inflation_radius / cost_scaling_factor | 0.35 m / 5.0 | 代价地图膨胀半径与衰减斜率 |
| controller_frequency | 10 Hz | move_base 局部规划刷新频率 |
| EKF frequency / two_d_mode | 30 Hz / true | 融合更新频率与 2D 运动约束 |
| cmd_vel→ctrl_cmd 心跳 | 100 Hz | 满足底盘 ≥30 Hz 控制硬性要求 |

## 实测性能

- RTAB-Map 重定位时间：< 5 秒（上电即完成）
- 30 米闭环巡检累积定位误差：< 8 cm
- CAN 控制频率：100 Hz（cmd_vel→ctrl_cmd 心跳） / 30 Hz（底盘 ctrl_fb 反馈）
- EKF 融合后 yaw 累积误差：< 0.5°

## 许可

本项目代码遵循各子模块原始许可：
- ORB_SLAM3：GPLv3
- DepthAI SDK：MIT
- IndoorMapping：MIT
- fw_odom_publisher：自研代码

# SOP 02 Jetson 环境安装

> 目前只写了第三方依赖这一节（2026-10-21 在 Jetson 上实际跑通）。系统、ROS、CAN、雷达网络等其余部分在 P0 验收时补上。

## 1. 第三方依赖（Livox-SDK2、livox_ros_driver2、FAST_LIO、small_gicp）

规则（CLAUDE.md 硬规则 7）：第三方源码不进 `ros_ws/src`。版本固定在 `thirdparty/repos.yaml`，我们的修改是 `thirdparty/patches/<仓库>/*.patch`，编译产物在 `thirdparty_ws/`（不入库）。

### 1.1 前置
```bash
sudo apt install -y python3-vcstool python3-catkin-tools
```
期望：`which vcs` 有输出。

### 1.2 一键拉取、打补丁、编译
```bash
cd ~/slam_car_tracking
./tools/setup_thirdparty.sh            # = fetch → patch → sdk → build → status
```
期望：
- 打印 `已打补丁 FAST_LIO/0001-…`、`0002-…`
- 如果 `/usr/local/lib/liblivox_lidar_sdk_static.a` 已经存在，sdk 步骤打印"跳过安装"，不需要 sudo；不存在时会要求输入 sudo 密码，安装到 /usr/local
- 最后 catkin 编出 4 个包（catkin_tools_prebuild、livox_ros_driver2、fast_lio、small_gicp），status 全部 ✔（例外：SDK 已经装在 /usr/local 但不是本脚本装的，没有安装标记，status 对 SDK 给出 `!` 提示，可以忽略；想消掉就执行一次 `./tools/setup_thirdparty.sh sdk --force`）

不对时：
- `kLivoxLidarTypeMid360s is not a member` → 驱动版本和 SDK 版本不匹配。驱动 master 需要 SDK v1.3.1，我们固定的是驱动 `6b9356c` + SDK v1.2.5，检查 `status` 里驱动的 commit
- `git apply` 失败 → 仓库不在 repos.yaml 固定的 commit 上，先 `./tools/setup_thirdparty.sh fetch`
- 拉取超时 → 检查代理（docs/02 第 1 节）
- 链接时警告 `libboost_xxx.so.1.71.0 ... may conflict with libboost_xxx.so.1.80.0` → `/usr/local` 下装了别的 boost，gcc 和 CMake 都会优先用它，和 ROS/PCL 的 boost 1.71 混在一起。本机的 boost 1.80（给 `~/projects/pcl` 自编的 PCL 1.15 用）已经在 2026-10-21 移到 `/opt/boost-1.80`；`check_env.sh` 会检查这一项。移走后要 `catkin clean` 再重编

单独执行某一步：`fetch` / `patch` / `sdk [--force]` / `build` / `status`。`fetch` 和 `patch` 可以重复执行，结果不变。

### 1.3 让 ros_ws 叠加在 thirdparty_ws 上（只需一次）
```bash
cd ~/slam_car_tracking/ros_ws
catkin config --extend ~/slam_car_tracking/thirdparty_ws/devel
catkin clean -y && catkin build && catkin test
source devel/setup.zsh
rospack find fast_lio              # 期望：路径在 thirdparty_ws/src 下（rospack find 一次只能查一个包）
rospack find livox_ros_driver2     # 同上
```
改了 extend 路径必须先 `catkin clean`，否则 catkin 会报工作空间链不一致。

### 1.4 升级第三方版本
1. 改 `thirdparty/repos.yaml` 里的 commit，在注释里写明原因
2. `./tools/setup_thirdparty.sh`；补丁打不上时，在新版本上重新做补丁（`git format-patch`），覆盖 `thirdparty/patches/` 下的旧文件
3. 用存档的 bag 回归，指标不能变差；单独提交

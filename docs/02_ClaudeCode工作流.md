# Claude Code 多 Agent 工作流（Linux 终端版）

## 0. 分工

| 角色 | 是谁 | 负责 |
|---|---|---|
| **你** | 人 | 定方向、确认计划、**执行一切会让车动的操作**、拿遥控器、读卷尺、在车上观察现象 |
| **主会话** | 运行在 Jetson 上的 `claude` | 统筹：拆任务、写核心代码、集成、调用子代理 |
| **子代理** | `.claude/agents/` 里的 6 个 | 在独立上下文中完成专门的工作，只把结论交回主会话，不占用主会话的上下文 |
| **并行会话** | 不同 git worktree 里各开一个 `claude` | 同时开发互不相关的包 |

本仓库已经配置好的内容：

```
CLAUDE.md                  每次会话自动加载：项目事实、硬规则、安全规则
.claude/settings.json      权限：只读命令直接放行；会让车动的命令、sudo、强推每次都要确认；commit / push 自动执行
.claude/agents/            ros-architect · ros-reviewer · test-engineer · bag-analyst · nav-tuner · doc-keeper
.claude/commands/          /session-start · /session-end · /field-test · /phase-gate
```

---

## 1. 安装（在 Jetson 上做，推荐从 PC 通过 SSH + tmux 登录）

建议直接在 Jetson 上运行 Claude Code，因为编译、单元测试、`candump`、`rostopic`、rosbag 都在 Jetson 上，Claude 可以直接验证自己写的东西。

```bash
# PC 上
ssh nvidia@<jetson-ip>

# Jetson 上
sudo apt install -y tmux git
curl -fsSL https://claude.ai/install.sh | bash      # 官方原生安装脚本，支持 Linux arm64
# 备选：npm install -g @anthropic-ai/claude-code（需要 Node 18+；Ubuntu 20.04 自带的 node 太旧，用 nvm 装）

# 如果需要代理才能访问外网
export HTTPS_PROXY=http://<代理地址>:<端口>   # 写进 ~/.zshrc

git clone https://github.com/zhilinqi9/slam_car_tracking.git ~/slam_car_tracking
cd ~/slam_car_tracking
claude          # 第一次运行时按提示登录
```

确认配置已生效：在 claude 里输入 `/agents`，应该能看到 6 个项目子代理；输入 `/`，补全列表里应该有 `session-start` 等命令。

> 仓库里只有代码和文档。厂家手册 PDF 放在本地 `refs/`（不入库），需要时从 PC 拷过去：
> `scp -r E:/slam_car_tracking/refs nvidia@<jetson-ip>:~/slam_car_tracking/`
>
> **两台机器同时用时**：每次开始前 `git pull --ff-only`，结束时 `/session-end` 会自动提交并推送。不要在 PC 和 Jetson 上同时改同一个分支。

---

## 2. 三种多 Agent 用法

### 方式 A：主会话 + 子代理（最常用，覆盖 80% 的场景）

子代理在**独立的上下文**里工作，读多少文件都不会撑满主会话，最后只交回结论。适合**读多写少**的工作：调研、审查、数据分析、写文档。

直接用自然语言调用：

```
用 ros-architect 设计 fw_chassis_node 的接口和参数，先不写代码
用 ros-reviewer 审查当前的改动
让 bag-analyst 分析 data/bags/2026-10-21_p1-odom.bag，对照 P1 的验收门槛
```

并行调用（一句话里点名多个子代理，它们会同时运行）：

```
并行做三件事：
1) ros-architect 设计 safety_guard 的停车区几何模型
2) test-engineer 给 protocol.hpp 补边界测试
3) bag-analyst 统计昨天那个 bag 里 /wheel/odom 的频率抖动
```

注意：**不要让两个子代理同时改同一批文件。** 需要改代码的并行任务用方式 B。

### 方式 B：git worktree + tmux 并行会话（并行开发独立模块）

每个 worktree 是一份独立的工作副本，有独立的分支和独立的 `ros_ws/build`、`ros_ws/devel`，几个 Claude 同时编译也不会互相干扰。

```bash
cd ~/slam_car_tracking
git worktree add ../car-follower -b feat/path-follower
git worktree add ../car-safety   -b feat/safety-guard

tmux new -s car                          # 窗口 0：主会话（集成 + 上车）
# Ctrl-b c 新建窗口
cd ../car-follower && claude             # 窗口 1：开发 path_follower
# Ctrl-b c
cd ../car-safety && claude               # 窗口 2：开发 safety_guard
# Ctrl-b <数字> 切换窗口；Ctrl-b d 断开（SSH 断线后 Claude 照样运行），tmux a -t car 重新连上
```

给每个并行会话的第一句话要把边界说清楚：

```
你在 worktree feat/path-follower 里工作，只改 ros_ws/src/fw_navigation/ 下的 path_follower 相关文件。
接口按 docs/01 第 1.2 节约定：订阅 /odometry/filtered 和 TF map→base_footprint，输出 /cmd_vel_nav。
只做单元测试，不连真车、不启动 roscore。完成后运行 catkin test，然后用 ros-reviewer 自查。
```

并行时的规则：
- **硬件锁**：只有主会话（主 worktree）可以连真车；其他 worktree 只做编译和单元测试
- 如果需要 roscore（例如 rostest），每个 worktree 用不同的端口：`export ROS_MASTER_URI=http://localhost:11312` 加 `roscore -p 11312`
- 合并：回到主会话，先 `用 ros-reviewer 审查 feat/path-follower 分支`，没有问题再 `git merge feat/path-follower` 并 `git push origin main`，最后 `git worktree remove ../car-follower` 和 `git branch -d feat/path-follower`（远端分支用 `git push origin --delete feat/path-follower` 删除）。每个 worktree 里的会话结束时同样要跑 `/session-end`，把分支推到远端
- 较新版本的 Claude Code 可能内置了 worktree 相关的启动参数，可以用 `claude --help` 查看；上面的手动方式在任何版本都能用

### 方式 C：无头模式 `claude -p`（脚本化、批处理）

适合不需要交互的固定任务，例如测完车后自动出报告：

```bash
claude -p "用 bag-analyst 分析 data/bags/2026-10-25_p4-loop10.bag，对照 P4 验收门槛，报告写到 data/reports/" \
  --allowedTools "Read,Grep,Glob,Write,Bash(rosbag info:*),Bash(python3:*)"
```

---

## 3. 一次标准的工作会话

```
┌─ /session-start [今天想做什么] ── 读日志和里程碑，给出今天 3–5 个任务及验收方式 ── 你确认
│
├─ Shift+Tab 切到 Plan 模式 ── 主会话（或 ros-architect）出方案 ── 你确认
│
├─ 实现：主会话写核心代码；可以并行的部分交给子代理（A）或 worktree（B）
│        catkin build && catkin test 必须全绿
│
├─ 用 ros-reviewer 审查 ── 修掉所有 🔴
│
├─ 需要上车时：/field-test <测试名> ── 生成测试单 ── 【你】按测试单操作、录 bag
│        回来后：让 bag-analyst 分析 <bag> ── 得到指标 ✅/❌
│        指标不达标：nav-tuner 根据数据调一组参数 → 再测（每轮只改一组）
│
├─ 阶段收尾时：/phase-gate P? ── 逐项核对证据
│
└─ /session-end [你在车上看到的现象] ── clean.sh 清理 → doc-keeper 写日志和 SOP → 自动 commit + push
```

**每次工作都会留下记录并同步到 GitHub**：`/session-end` 会先运行 `tools/clean.sh` 清理垃圾文件，最后提交并推送，回复里会给出 commit hash。`/session-end` 每次都会生成 `docs/worklog/日期_主题.md`（包括"本次操作说明"一节）；操作流程有变化时会同步更新 `docs/sop/`。

---

## 4. 各阶段的推荐分工

| 阶段 | 主会话 | 并行 / 子代理 |
|---|---|---|
| P0 环境 | 跑 `check_env.sh`，逐项安装和修复 | — |
| P1 底盘 | 写 `fw_chassis_node` | ros-architect 先出接口设计；test-engineer 写积分和超时逻辑的测试；上车后交给 bag-analyst |
| P2 传感器 | URDF + EKF | worktree：`fw_tools` 的 bag 指标脚本（odom 误差、频率统计） |
| P3 建图定位 | slam_toolbox / AMCL 的 launch | bag-analyst 做定位重复性分析；nav-tuner 调 AMCL |
| P4 示教复现 | 集成 + 上车 | worktree A：path_recorder + path_follower；worktree B：safety_guard；test-engineer 写几何测试 |
| P5 鲁棒性 | 按需 | 方式 C：每次测完车自动出报告 |

---

## 5. 常用操作速查

| 操作 | 作用 |
|---|---|
| `claude` / `claude -c` / `claude -r` | 新会话 / 继续上一次会话 / 从历史会话中选一个恢复 |
| `Shift+Tab` | 循环切换：普通 → 自动接受编辑 → **Plan 模式**（只出方案不改代码） |
| `Esc` / `Esc Esc` | 打断当前操作 / 回到之前的某条消息重新编辑 |
| `@文件路径` | 把指定文件加入上下文 |
| `!命令` | 直接执行 shell 命令，输出会进入上下文（例如 `!rostopic hz /scan`） |
| `/clear` | 换一个不相关的任务时清空上下文（CLAUDE.md 会重新加载） |
| `/compact` | 压缩长对话，保留要点 |
| `/agents` | 查看、新建、编辑子代理 |
| `/model` | 切换模型 |
| `/permissions` | 查看和修改权限规则 |
| `/code-review` | 内置的改动审查（和 ros-reviewer 互为补充） |

效率建议：
1. **一个任务一个会话**：做完一件事就 `/session-end`，然后 `/clear`。上下文越干净，Claude 越准确
2. **给子代理的任务要窄**：说清楚输入、输出、不能碰哪些文件
3. **让 Claude 自己验证**：要求"改完运行 catkin test，并贴出结果"
4. **上车数据交给 bag 分析**：不要靠描述"感觉跑偏了"，录 bag 让 bag-analyst 算横向误差
5. **CLAUDE.md 只放长期有效的事实**：临时信息写在工作日志里

---

## 6. 安全底线

- **不要在这个项目里使用 `--dangerously-skip-permissions`**。机器人会动，`settings.json` 里的 `ask` 规则是最后一道防线
- Claude 请求执行 `rostopic pub`、`roslaunch`、`cansend` 时，先确认：车是否架空或场地是否清空、遥控器是否在手、限速是多少
- 自主运行时，人必须站在急停按钮旁边，遥控器 SWA 拨杆随时可以接管

## 7. 可选：Hook

例如每次会话启动时自动显示最新一篇日志的文件名（加进 `.claude/settings.json`，用 `/hooks` 确认生效）：

```json
"hooks": {
  "SessionStart": [
    { "hooks": [ { "type": "command",
      "command": "ls -1 docs/worklog/20*.md 2>/dev/null | tail -1 | sed 's/^/最新工作日志: /'" } ] }
  ]
}
```

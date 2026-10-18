---
description: 会话结束：清理垃圾、写工作日志、更新操作说明和里程碑、提交并推送 git
argument-hint: [补充说明，比如用户在车上观察到的现象]
---

1. **清理**：运行 `./tools/clean.sh`。它列出的每个未跟踪文件都要处理：有用的纳入本次提交；没用的删除；属于本地产物的加入 `.gitignore`。处理完再运行一次，确认没有未处理的文件
2. **验证**：如果本次改了代码，运行 `cd ros_ws && catkin build && catkin test`，记下结果（Windows 上没有 ROS 时注明"未在 catkin 下验证"）
3. **审查**：本次改了代码但还没审查过的，调用 **ros-reviewer** 子代理；🔴 级问题要么当场修掉，要么写进日志的"遗留问题"
4. **收集事实**：`git status --short`、`git diff --stat`、本次会话的提交、运行过的编译 / 测试 / 上车命令的结果、`data/bags/` 下今天新增的 bag
5. 用户补充说明：$ARGUMENTS
6. **写文档**：调用 **doc-keeper** 子代理，把以上事实交给它：
   - 按 `docs/worklog/TEMPLATE.md` 写或追加今天的日志 `docs/worklog/YYYY-MM-DD_<主题>.md`
   - 操作流程有变化时更新 `docs/sop/` 下对应的 SOP 和索引
   - 勾选已经通过验收的里程碑条目
7. **提交并推送**（用户的长期要求，不需要再次确认）：
   - 代码和文档分开提交，中文提交信息 `<包名>: <做了什么>`，末尾带 Co-Authored-By 行
   - 测试全部通过 → 提交到当前分支并 `git push origin <分支>`；测试不通过 → 提交到 `wip/<主题>` 分支并推送，日志里写明原因
   - 推送前先 `git fetch`；远端有新提交时用 `git pull --ff-only`，无法快进就停下来报告，**不要强推**
8. 最后确认 `git status` 是干净的

最后用 5 行以内总结：完成了什么、commit hash、是否已推送、阶段进度、下次第一件事做什么。

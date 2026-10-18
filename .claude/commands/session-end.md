---
description: 会话结束：写工作日志、更新操作说明和里程碑、准备提交
argument-hint: [补充说明，比如用户在车上观察到的现象]
---

1. 收集事实：`git status --short`、`git diff --stat`、`git log --oneline` 中本次会话的提交，以及本次会话里运行过的编译、测试和上车命令的结果，`data/bags/` 下今天新增的 bag
2. 用户补充说明：$ARGUMENTS
3. 调用 **doc-keeper** 子代理，把以上事实交给它，让它：
   - 按 `docs/worklog/TEMPLATE.md` 写或追加今天的日志 `docs/worklog/YYYY-MM-DD_<主题>.md`
   - 操作流程有变化时更新 `docs/sop/` 下对应的 SOP 和索引
   - 勾选已经通过验收的里程碑条目
4. 如果本次改了代码但还没有审查过，调用 **ros-reviewer** 子代理审查，🔴 级问题在日志的"遗留问题"中列出
5. 给出建议的 commit 拆分（代码和文档分开提交）和中文提交信息，**等用户确认后再 commit**；不要 push

最后用 5 行以内总结：今天完成了什么、阶段进度、下次第一件事做什么。

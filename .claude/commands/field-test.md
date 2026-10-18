---
description: 生成上车测试单（安全检查 + 步骤 + 录包命令 + 判定标准），测试由人执行
argument-hint: <测试名称，如 p1-sign-calib / p4-loop10>
---

为测试「$ARGUMENTS」生成测试单，保存到 `docs/worklog/tests/<今天日期>_$ARGUMENTS.md`，并在对话里展示。

测试单的内容：
1. **目的与验收门槛**：从 `docs/01_技术路线与里程碑.md` 中摘出对应条目，写明具体数值
2. **前置条件**：车要架空还是落地、场地大小、需要的地面标记、电量 ≥ 30%、遥控器在手、限速参数（参照 `docs/sop/00_安全规范.md`）
3. **启动命令**：按终端分组，每条写明期望看到的输出
4. **录包命令**：
   `rosbag record -O data/bags/<日期>_$ARGUMENTS.bag /tf /tf_static /wheel/odom /odometry/filtered /imu /scan /cmd_vel /cmd_vel_nav /chassis/state /amcl_pose`（按测试内容增减；默认不录图像）
5. **操作步骤**：逐步写明人要做什么（遥控怎么走、在哪里停、重复几次），以及每一步需要记录的人工观测（卷尺读数等），并留出空白表格供填写
6. **中止条件**：出现哪些现象时立即拍急停或拨 SWA
7. **事后分析**：交给 bag-analyst 时要附带的信息

**不要执行任何会让车动的命令。** 测试单生成后，提醒用户按测试单操作；回来之后用 bag-analyst 分析。

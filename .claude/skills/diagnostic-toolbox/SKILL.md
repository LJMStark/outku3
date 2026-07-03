---
name: diagnostic-toolbox
description: Kirole 仓库自带诊断工具地图：eink-simulator、虚拟硬件测试(BLEProtocolSimulationTests)、frame trace、keep-alive、PromptDebugger、fastlane status、ASC 校验脚本。需要观察现场（帧/prompt/显示/发布状态）时查这份。NOT for 排查流程本身（去各 runbook）——本页只讲工具在哪、怎么开、有什么坑。
---

# 诊断工具箱

## 适用

- 排查中需要"看到"数据/帧/prompt/发布状态的现场
- 无硬件、无网络时想验证 BLE / 显示行为
- 想确认某个调试开关为什么可见/不可见

## 不适用

- 该按什么顺序排查 → `ble-sync-runbook` / `testflight-distribution-runbook` / `flaky-test-triage`
- 工具输出显示的行为像 bug → 先查 `intentional-behaviors-contract`

## 硬件不在场时的两级仿真

1. **虚拟硬件测试**（最快，无 UI）：`BLEProtocolSimulationTests` +
   `BLEProtocolSimulationSupport.swift` 的严格镜像解码器——逐字节重放 wire、`requireEnd()`
   校验尾部。它就是"固件的替身"（`4e3388d` 起建，`f4c45c5` 曾用它证明 ASCII 保证）。
   跑法：`cd KirolePackage && swift test --filter BLEProtocolSimulationTests`。
2. **eink-simulator/**（有 UI，看显示效果）：网页版 E-ink 仿真器。
   - 结构：`server.js`（WebSocket 中继）+ `src`/`dist`（前端）；
   - 中继在 **:3456** 上 fan-out（`2a3042f`），网页端默认 ws-url 已对齐 :3456（`8e3e7ae`），
     加载即自动连接（`7e91296`）；
   - 用途：不烧固件就目验 DayPack 排版、分包重组效果。

## App 内调试开关（真机/TestFlight）

- **总门**：`AppBuildEnvironment.showsHardwareDebugTools`（`Core/Config/AppBuildEnvironment.swift:36`）。
  当前**恒 true 全包可见**——这是联调期临时态（真机 isTestFlight 判定不可靠，`cdf1dc7`），
  上架前恢复门控（改法在同文件注释）。"为什么正式包也能看到调试区"的答案就是这条。
- **BLE frame trace**：帧级收发日志，TestFlight 包可见（`d83679d`）。联调争议（"App 到底发没发"）
  以 trace 为准，别对猜。
- **keep-alive debug mode**：`BLEService.keepAliveDebugMode`（UserDefaults key
  `bleKeepAliveDebugMode`，默认开，`82a8d6c`）。诊断"连接被系统回收"类问题先看它的状态。
- **BLE trusted device reset**（`bd8174b`）：设备信任列表清空入口，配对异常时用。
- **PromptDebugger（+FAB）**：看实际组装的 prompt。注意门控历史——prompt 注入面必须
  `#if DEBUG`（`3800498`），FAB 入口的门控曾被误改并回退（`e8236a3`）；改它前先读现状。
  mock context 会保留 customCompanion（`67b6e86`），所以自定义伴侣的 prompt 也能在此调试。

## 用户可见的状态面（排查时先看，别直接上日志）

- Settings 齿轮红点 + 集成区行内错误 + **syncStatusCard 三层状态**（黄色警告/离线/最后同步
  时间，`5f80547`）——错误呈现的唯一产品面（时间线横幅已删，别找横幅）。
- 日志导出：provider 错误原文已被滤掉（`00e9a80`），导出日志里看不到上游错误细节是故意的。

## 发布/分发侧工具

- `fastlane ios status` —— ASC 真源核验（processingState / internal / external state），
  发布后必跑（`413c928`）。
- `fastlane ios finish_external` —— 半路死掉的发布的幂等收尾（`cb43627`）。
- `./check_testflight_ready.sh` —— 发布前环境自检（2 月置备，跑前 `cat` 一眼确认还适用）。
- `./verify_family_controls.sh` —— Family Controls 能力核验（Focus 强制模式相关）。

## 构建会话工具

- XcodeBuildMCP：每个会话第一次 build 前先 `session_show_defaults` 确认 project/scheme/simulator
  （项目惯例，写在 CLAUDE.md）；日志抓取用 `start_sim_log_cap` 系列。

## 姊妹文档

- `ble-sync-runbook` — 这些工具在排查流程里的调用顺序
- `testflight-distribution-runbook` — status / finish_external 的出场时机
- `llm-prompt-safety-contract` — PromptDebugger 触碰的注入面约束
- `release-acceptance` — 上架前必须关掉哪些"临时全开"

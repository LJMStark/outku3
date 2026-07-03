---
name: ble-sync-runbook
description: 硬件不显示新数据、sync 不触发、连接卡死、离线补传(0x21 eventLogBatch)丢失时的联调排查手册。第一反应"硬件没收到"往往是同步节流特性（DayPack 指纹 / 0x20）。NOT for 改 wire 字节（去 ble-wire-change-control）或"这行为是不是 bug"（去 intentional-behaviors-contract）。
---

# BLE 同步 / 联调排查手册

## 适用

- "App 加了任务，硬件不显示"
- 同步轮次失败、硬件收不到 DayPack、0x20 风暴
- 连接卡在扫描、断连后数据错乱、离线事件补传丢失

## 不适用

- 要改字节格式 → `ble-wire-change-control`
- 行为怪但可能是故意的 → 先查 `intentional-behaviors-contract`（本页多处会指过去）
- 需要工具本身的用法（frame trace / 仿真器）→ `diagnostic-toolbox`

## 症状 1："加了任务硬件不显示" —— 90% 是特性

同步有节流（`BLESyncCoordinator.performSync()` + `BLESyncPolicy`）：白天 08–23 每 1 小时、
夜间 23–08 每 4 小时。触发时机只有四种：iOS `BGAppRefreshTask`、硬件主动 `0x20`/`0x30`、
DayPack 指纹变化、`force: true`。**用户加任务后硬件本来就不会立刻显示**。

排查顺序：

1. 确认是否在节流窗口内 → 是则为正常行为，别修；
2. 用户写路径应触发 sync（`8a2787d` 加过 user-write → sync 的钩子），确认改动没绕开它；
3. 查 DayPack 指纹是否真的变了——指纹没变就不推。指纹的坑有前科：off-wire 内容混入
   （`4603d3a`）、分隔符未转义导致碰撞（`095f28f`）、locale 影响（`bf1c057`）。

## 症状 2：同步轮次"成功"但硬件没数据

"写出去了"不等于"这轮成功"。已建立的语义：`0x20` 事件日志请求写失败 = 整轮失败
（`a79a21f`）；DayPack 写失败 = 整轮失败（`059aaea`）。排查时先看 Settings 的
syncStatusCard 分层状态（黄色警告/离线/最后同步时间，`5f80547`），再看 frame trace。

## 症状 3：0x20 风暴 / 同步过于频繁

固件把 `RequestRefresh(0x20)` 当 ~2 秒心跳发。App 侧已定为 **60 秒合并窗**去抖
（`d673f80`，v2.5.14 §8.5）。注意历史教训：第一版是硬抑制（`1abb44b`），直接把合法刷新
也压死了，后来才改成合并。调这个参数时别回到"硬抑制"老路。

## 症状 4：连接 / 断连异常

- 卡在扫描不动：重连状态机曾有 stuck-scanning hang，`efe7d66` 硬化过；连接超时用
  generation 计数防串台（`d83679d`）。复现时先抓 frame trace 再猜。
- 断连后数据错乱：断连必须重置 `packetAssembler`（`86cd9a2`，协议 v2.5.2 文档化），
  slot-full 丢包有日志。半包残留 + 新连接 = 解析错位的经典来源。
- 联调期 keep-alive 默认开（`82a8d6c`），入口在 `BLEService.keepAliveDebugMode`
  （UserDefaults `bleKeepAliveDebugMode`）。诊断时先确认它的状态。

## 症状 5：离线补传（0x21 eventLogBatch）丢事件

补传是核心功能（硬件优先），丢失事件的已知坑位：

- **毒化水位线**：一条坏事件把 `lastEventLogTimestamp` 推过头，后续合法事件全被
  当旧事件跳过（`7f9eb4c` 修过）；
- **replay 与 live 的分工**：replay 只应用状态变更（completeTask 等），**不触发**副作用
  （TaskInPage 回发、feedback、通知，`b54248c`）。看到"replay 没发通知"别当 bug；
- **replay 跳过 enterTaskIn 是故意的**（`guard !isReplay`，`4c20510` 文档化）：
  专注时长以 App 为准，不按硬件时间戳补算 → 详见 `intentional-behaviors-contract`；
- 批量入库有幂等过滤 + 排序（`1cc94fe`），重复事件不该产生重复状态变更。

## 症状 6：后台同步随机中断

`BGAppRefreshTask` 到期必须 finalize，否则 watchdog 杀进程（`a4b6237`）。
后台轮次神秘消失时先查 expiration handler 是否被新代码绕开。

## 姊妹文档

- `diagnostic-toolbox` — frame trace、keep-alive、eink-simulator、硬件调试开关的用法
- `intentional-behaviors-contract` — 节流、replay 跳过、Mood 通道等"别修"清单
- `ble-wire-change-control` — 排查结论是"格式不对"时的变更流程
- `failure-archaeology` — 0x20 风暴、stuck-scanning 的完整事故记录

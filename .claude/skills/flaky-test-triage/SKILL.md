---
name: flaky-test-triage
description: 测试忽红忽绿、只在全量跑挂、单跑却绿时的排查手册（Swift Testing 并行隔离、SharedPersistenceTestLock、resettableUserDefaultKeys）。NOT for 编译错误（swift-build-resolver）或仿真解码器 trailingBytes 红（那是 wire desync，去 ble-wire-change-control）。
---

# Flaky 测试排查手册

## 适用

- 某 suite 全量 `swift test` 时挂、`--filter` 单跑时绿
- 新加了一个 key / 一个测试后，**别人的**老测试开始随机红
- CI 没有（本仓库无测试 CI），所以 flaky 都出现在本地全量跑

## 不适用

- 编译失败 → build 错误流程（swift-build-resolver agent）
- `BLEProtocolSimulationTests` 报 `trailingBytes` → 不是 flaky，是 wire 与镜像解码器 desync，
  去 `ble-wire-change-control` 铁律 1
- 一直红（确定性失败）→ 正常调试，本文只管"忽红忽绿"

## 根因模型：Swift Testing 并行 + 全局 UserDefaults

Swift Testing **并行跑所有 suite**。本仓库的持久化中枢 `LocalStorage` 走全局
`UserDefaults.standard`，两个 suite 同时读写同一个 key 就互相污染。这是本仓库 flaky 的
唯一大类根因，其他原因（时序、网络）在这个纯本地测试体系里几乎不存在。

## 排查顺序（严格按序，别跳步）

1. **单跑确认**：`cd KirolePackage && swift test --filter SuiteName`。
   - 单跑绿 + 全量红 → 隔离问题，继续第 2 步；
   - 单跑也红 → 不是 flaky，正常调试去。
2. **找共享状态**：该 suite 是否直接或间接（经 `LocalStorage`、focus 能量瓶、gamify 存储）
   碰了 `UserDefaults.standard`？
3. **加锁而不是改生产代码**：测试体包进
   `await SharedPersistenceTestLock.shared.withLock { ... }`
   （`Tests/KiroleFeatureTests/SharedPersistenceTestLock.swift`）。
   **千万别**因为测试 flaky 去回退生产修复——这条是用户立的规矩。
4. **确认锁覆盖完整**：锁要包住"写入 → 断言 → 清理"全程，只包写入照样漏。

## 高危操作：往 resettableUserDefaultKeys 加 key

`LocalStorage.resettableUserDefaultKeys` 每加一个 key，所有碰全局 `.standard` 的既有测试
都可能变 flaky（reset 路径会扫这个清单）。加 key 的 PR 必须同时检查哪些既有 suite 需要补锁。
实例修复：

- `6a74348` — `pendingCustomCompanionPushId` 的访问补锁
- `3131468` — 硬化 focus-session range 与 dev reset keys 本身

## 状态泄漏的另一形态：跨测试的时间戳水位线

`822d086` 修过 P0-1 回归：BLE replay 测试没重置 `lastEventLogTimestamp`，前一个测试留下的
水位线让后一个测试的事件被当成"已处理"静默吞掉。断言"事件没被处理"失败时，先查
水位线/去重游标类状态是否在测试间残留。

## 长期停用的测试

`8fc5e88` 把 `securityHandshakeFailed` 测试标为 disabled（pre-existing 失败）。
遇到 disabled 测试别顺手删——它是墓碑，激活条件（secure 模式联调）到了要重启它。

## Runner 选择备忘

- 逻辑/服务测试：`swift test`（快，包级）
- 碰 App 壳 / UI 生命周期：`xcodebuild ... test` 或 XcodeBuildMCP `test_sim`
- 两个 runner 的并行行为一致，隔离规则同样适用

## 姊妹文档

- `ble-wire-change-control` — 仿真解码器红的处理
- `ui-change-acceptance` — UI 改动该跑哪些验证
- `failure-archaeology` — P0-1 回归的完整背景

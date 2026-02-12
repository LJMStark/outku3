# Kirole iOS App - MVP 交付差距分析报告

> 基于 PRD v0.5、硬件规格文档 v1.1.0、BLE 协议规格 v1.1.0 与当前代码库的综合对比分析
> 分析日期: 2026-02-09

---

## 一、总体评估

**代码库完成度: ~75%** — 63 个源文件全部有实际实现（无空壳），架构清晰，MV 模式规范。但存在若干关键差距需要在交付前解决。

| 维度 | 状态 | 说明 |
|------|------|------|
| 架构 & 代码质量 | 良好 | MV 模式、Swift 6 并发、Actor 隔离 |
| BLE 协议实现 | 需对齐 | 9 字节 header vs 硬件 3 字节 header |
| 核心功能 (P0) | 基本完成 | 配对、DayPack、任务、宠物、同步 |
| Focus Challenge (P1) | 部分实现 | 缺少 Screen Time API 集成 |
| 测试覆盖率 | ~40-50% | 目标 80%，缺少大量服务测试 |
| 天气功能 | 未实现 | 硬编码数据，无真实 API |
| AI 文本生成 | 部分实现 | CompanionText 仅用本地模板 |

---

## 二、CRITICAL — 必须修复 (阻塞交付)

### 1. BLE 协议 Header 格式不匹配

**现状**: `BLEPacketizer` 使用 9 字节 header:
```
type(1) | messageId(2) | seq(1) | total(1) | payloadLen(2) | crc16(2)
```

**硬件规格要求**: App->Device 使用 3 字节 header:
```
type(1) | length(2, Big Endian) | payload(N)
```
Device->App 使用 2 字节 header:
```
type(1) | length(1) | payload(N)
```

**影响**: 与真实硬件通信将完全失败
**建议**:
- 保留 `BLEPacketizer` 用于大 payload 分包场景（未来 CRC 扩展）
- 新增 `BLESimplePacketEncoder` 实现硬件规格的简单 header 格式
- `BLEService` 发送时默认使用简单格式
- 接收时根据实际 header 长度自动判断格式
### 2. 设备事件处理不完整

**现状**: `BLEEventHandler.handleReceivedPayload()` 仅处理 `eventLogBatch`，其他事件类型全部 `break` 忽略。

**缺失处理**:
| 事件 | 类型码 | 需要的响应 |
|------|--------|-----------|
| `RequestRefresh` (0x20) | 设备请求刷新 | 应立即推送新 DayPack |
| `DeviceWake` (0x30) | 设备唤醒 | 应同步时间 + 推送数据 |
| `LowBattery` (0x40) | 低电量 | 应向用户显示通知 |
| `SelectedTaskChanged` (0x13) | 任务切换 | 应更新 App 中选中状态 |
| `EnterTaskIn` (0x10) | 进入任务 | 应回传 TaskInPage 数据 |
| `ViewEventDetail` (0x15) | 查看日程 | 应回传日程详情 |

**建议**: 扩展 `handleReceivedPayload` 的 switch 分支，为每种事件实现对应响应逻辑。

### 3. EventLog 解析格式双重标准

**现状**: `EventLog.parseRecord` 使用 7 字节固定格式 (type + timestamp + value)，而 `parseLegacyEventLog` 使用长度前缀字符串格式 (type + taskIdLen + taskId + timestamp)。

**硬件规格**: Device->App 事件使用 `type(1) + length(1) + payload(N)` 格式，其中 payload 包含长度前缀的 TaskId + UInt32 timestamp。

**建议**: 统一为硬件规格定义的格式，移除 7 字节固定格式的 `parseRecord`，以长度前缀格式为主。

---

## 三、HIGH — 重要改进 (影响验收)

### 4. 天气数据完全硬编码

**现状**: `Weather()` 默认 22°C、San Francisco，无任何天气 API 调用。`SunTimes` 硬编码 6:45/17:30。

**PRD 要求**: Top Bar 显示天气/温度（标记为 optional 但影响体验）。DayPack 包含 Weather 命令 (0x04)。

**建议**:
- 集成 Apple WeatherKit 或 OpenWeatherMap API
- 使用 CoreLocation 获取用户位置
- 计算真实日出日落时间
- 如果暂不集成，至少允许用户手动设置城市

### 5. CompanionTextService 仅使用本地模板

**现状**: 所有伴侣文本（晨间问候、日程摘要、伴侣短语、任务描述、鼓励语）均从硬编码数组随机选取。

**PRD 要求**: AI 生成的朋友语气文本，表达关心，个性化。

**建议**:
- 当用户配置了 OpenAI API Key 时，使用 `OpenAIService` 生成个性化文本
- 保留本地模板作为 fallback（无网络/无 API Key）
- `DayPackGenerator` 中已有 async 文本生成接口，需要接入真实 AI 调用

### 6. Focus Challenge 缺少 Screen Time API 集成

**现状**: `FocusSessionService` 通过 `UIApplication` 通知追踪屏幕解锁，但这只能检测 App 前后台切换，无法检测用户使用了哪些分心类别的 App。

**PRD 要求 (P1)**:
- Screen Time / Family Controls 授权引导
- 类别级别的分心选择（社交/娱乐/游戏/购物）
- 检测会话期间是否使用了分心类别 App
- 会话结果: success | failed | unverified

**建议**:
- 集成 `DeviceActivityMonitor` (iOS 16+) 和 `FamilyControls` 框架
- 添加分心类别选择 UI（Settings 中）
- 实现 `ShieldConfiguration` 用于检测（非阻止）
- 降级路径: iOS <16 或未授权时标记为 unverified
### 7. Demo 模式需要增强

**PRD 要求**: Demo 模式必须支持"模拟 Focus Session 成功/失败/未验证"用于拍摄和直播演示。

**现状**: `DemoModeService` 存在但需验证是否覆盖 Focus Session 模拟场景。

---

## 四、MEDIUM — 质量改进 (提升交付质量)

### 8. 测试覆盖率不足 (~40-50%, 目标 80%)

**已有测试**: AppState (30 tests), AuthManager (5 tests), BLEProtocol (5 tests)

**缺失测试**:
| 模块 | 优先级 | 说明 |
|------|--------|------|
| BLEDataEncoder | HIGH | 验证编码输出与硬件规格一致 |
| BLEEventHandler | HIGH | 验证所有事件类型正确路由 |
| DayPackGenerator | HIGH | 验证 DayPack 内容完整性 |
| FocusSessionService | HIGH | 验证会话生命周期和专注时间计算 |
| BLESyncCoordinator | MEDIUM | 验证重试策略和指纹门控 |
| LocalStorage | MEDIUM | 验证持久化正确性 |
| CompanionTextService | LOW | 验证文本生成 |
| GoogleCalendarAPI | LOW | 需要 mock 测试 |

### 9. 代码质量问题

| 问题 | 位置 | 建议 |
|------|------|------|
| `SettingsView.swift` 超过 828 行 | Views/Settings/ | 拆分为子视图组件 |
| `AppState` 569 行 + 直接 mutation | State/ | 提取子状态管理器 |
| 残留 `print()` 语句 | GoogleCalendar, Supabase | 替换为 `os.Logger` |
| `toggleTaskCompletion` 直接修改数组元素 | AppState | 使用不可变模式 |

### 10. 数据源确认

**PRD 待确认**: MVP 是否需要同时支持 Google + Apple 双生态，还是先 iOS 原生？

**现状**: 代码已实现 Google Calendar/Tasks + Apple Calendar/Reminders，但 Todoist/Outlook/Notion 等标记为 `isSupported: false`。

**建议**: 确认 KS Demo 所需的最小数据源集合，移除或隐藏未支持的集成入口。

---

## 五、LOW — 优化建议 (锦上添花)

### 11. 日出日落时间计算
使用 `Solar` 算法或 CoreLocation 替代硬编码值。

### 12. 离线行为增强
PRD 要求设备断连时显示缓存数据，重连后自动推送新 DayPack。需验证 `BLESyncCoordinator` 的重连逻辑是否覆盖此场景。

### 13. 低电量通知
收到 `LowBattery` (0x40) 事件时，应通过 `UNUserNotificationCenter` 向用户推送本地通知。

### 14. 错误提示用户体验
BLE 连接失败时的用户提示需要更友好（蓝牙关闭 -> 引导开启，权限拒绝 -> 引导设置）。

---

## 六、优先级排序的改进路线图

### Phase 1: 硬件对接准备 (CRITICAL, 预计 3-5 天)
1. **对齐 BLE 协议 header 格式** — 新增简单 header 编码器
2. **完善设备事件处理** — 扩展 `BLEEventHandler` 所有事件分支
3. **统一 EventLog 解析格式** — 匹配硬件规格
4. **BLE 编码单元测试** — 验证每种数据类型的编码输出

### Phase 2: 功能补全 (HIGH, 预计 5-7 天)
5. **天气 API 集成** — WeatherKit 或 OpenWeatherMap
6. **AI 文本生成接入** — CompanionTextService 接入 OpenAI
7. **Demo 模式增强** — 支持 Focus Session 模拟
8. **数据源确认与清理** — 移除未支持的集成入口

### Phase 3: Focus Challenge (P1, 预计 5-7 天)
9. **Screen Time API 集成** — DeviceActivityMonitor + FamilyControls
10. **分心类别选择 UI** — Settings 中添加
11. **Focus Session 结果判定** — success/failed/unverified 逻辑
12. **降级路径实现** — iOS <16、未授权等场景

### Phase 4: 质量保障 (预计 3-5 天)
13. **补充单元测试** — 目标 80% 覆盖率
14. **代码质量修复** — SettingsView 拆分、print 清理、immutability
15. **集成测试** — BLE 端到端模拟测试
16. **验收测试** — 对照 PRD 验收标准逐项验证

---

## 七、PRD 验收标准对照表

### 主循环验收 (P0 Must Pass)

| # | 验收标准 | 代码状态 | 差距 |
|---|---------|---------|------|
| 1 | 4 页显示 + 正确切换规则 | DayPack 模型完整 | BLE header 需对齐 |
| 2 | Page 2: 日程摘要 + Top 3 任务 + 伴侣短语 | 编码器已实现 | 文本需 AI 化 |
| 3 | Page 3: 完成/跳过并返回 Page 2 | 事件处理已实现 | 需补全 EnterTaskIn 响应 |
| 4 | Page 4: 宠物成长 + 积分结算 | Settlement 数据完整 | 无重大差距 |
| 5 | App: 配对/DayPack/EventLog/模式切换/Demo | 全部已实现 | BLE 格式需对齐 |
| 6 | Focus 模式: 按钮不改变状态 | DeviceMode 已实现 | 需验证硬件端行为 |

### Focus Challenge 验收 (P1 If Enabled)

| # | 验收标准 | 代码状态 | 差距 |
|---|---------|---------|------|
| 1 | iOS 16+ 授权引导 + 开关 | 未实现 | 需新增 |
| 2 | 类别级分心选择 | 未实现 | 需新增 |
| 3 | EnterTaskIn 创建 30m Session | 已实现 | 基本完成 |
| 4 | 结算页显示成就 + 奖励 | 部分实现 | 需增强 |
| 5 | 降级路径不影响主循环 | 架构支持 | 需验证 |

---

*报告由 4 个并行分析 Agent 协作生成: codebase-auditor, prd-analyst, hardware-analyst, contract-analyst*

# Kirole BLE 联调前全协议模拟报告

**日期:** 2026-05-07  
**代码分支:** `codex/ble-protocol-sync`  
**模拟依据:** App 当前代码里的 `BLEDataEncoder`、`BLESimpleEncoder`、`BLEPacketizer`、`BLEService.decodeReceivedMessageForTesting`  
**测试文件:** `KirolePackage/Tests/KiroleFeatureTests/BLEProtocolSimulationTests.swift`  
**测试辅助:** `KirolePackage/Tests/KiroleFeatureTests/BLEProtocolSimulationSupport.swift`

---

## 1. 这次模拟做了什么

这次没有连接真实硬件，而是在 App 测试里写了一个虚拟硬件解析器：

- App 发出的包：按硬件视角拆 `type + length + payload` 和 9 字节分包。
- 设备回 App 的包：按 App 当前解析逻辑拆 `type + length + payload` 和 9 字节分包。
- 坏包：长度不对、CRC 不对、开发显示命令误走标准包，都会被拦下。
- 安全包：模拟 `BLE_SHARED_SECRET` 已配置时的 `SecureEnvelope` 包装和解包。

结论：App 当前 BLE 协议已经可以做第一轮软件联调模拟。真实硬件联调前，硬件团队仍要按本报告第 6 节确认几个边界。

---

## 2. App → Device 模拟结果

### 2.1 标准简单包

App → Device 简单包格式：

```text
------+--------------+---------+
| type | length(2BE) | payload |
+------+--------------+---------+
```

这次模拟覆盖：

| Type | 名称 | 模拟结果 | 关键字段 |
|---|---|---|---|
| `0x01` | `PetStatus` | 通过 | `Name`、`Mood`、`CharacterId` |
| `0x02` | `TaskList` | 通过 | 只发今日任务，最多 10 条 |
| `0x03` | `Schedule` | 通过 | 只发今日日程，时间为 `HH:mm` 原始 UTF-8 |
| `0x04` | `Weather` | 通过 | 温度为 `Int8`，天气字符串是 SF Symbols 名 |
| `0x05` | `Time` | 通过 | `Year-2000, Month, Day, Hour, Minute, Second` |
| `0x12` | `DeviceMode` | 通过 | `0x00=interactive`, `0x01=focus` |
| `0x13` | `SmartReminder` | 通过 | 文本、紧急程度、心情字母 |
| `0x20` | `EventLogRequest` | 通过 | `Since` 为 4 字节大端 UInt32 |

### 2.2 PetStatus 样例

输入：`Pet(name: "Tiko", mood: Happy)`，角色 `joy`。

```text
01 00 0A
04 54 69 6B 6F
48
03 6A 6F 79
```

字段解释：

| 字节 | 含义 |
|---|---|
| `01` | `PetStatus` |
| `00 0A` | payload 长度 10 |
| `04 54 69 6B 6F` | `"Tiko"` |
| `48` | mood = `H` |
| `03 6A 6F 79` | `CharacterId = "joy"` |

### 2.3 Weather 样例

输入：`temperature = -3`，`condition = cloud.rain.fill`。

```text
04 00 10
FD
0F 63 6C 6F 75 64 2E 72 61 69 6E 2E 66 69 6C 6C
```

硬件要注意：天气字符串目前不是 `rainy`，而是 App 里的 `WeatherCondition.rawValue`，也就是 `cloud.rain.fill` 这种 SF Symbols 名。

### 2.4 DeviceMode 样例

```text
12 00 01
01
```

字段解释：

| 字节 | 含义 |
|---|---|
| `12` | `DeviceMode` |
| `00 01` | payload 长度 1 |
| `01` | focus 模式 |

### 2.5 EventLogRequest 样例

输入：`since = 1767225600`。

```text
20 00 04
69 55 B9 00
```

---

## 3. App → Device 分包模拟结果

9 字节分包格式：

```text
type(1) + messageId(2BE) + seq(1) + total(1) + chunkLength(2BE) + crc16(2BE) + chunkPayload
```

这次模拟覆盖：

| Type | 名称 | 模拟结果 | 说明 |
|---|---|---|---|
| `0x10` | `DayPack` | 通过 | 虚拟硬件按 `messageId + seq` 重组后解析字段 |
| `0x11` | `TaskInPage` | 通过 | 虚拟硬件按分包重组后解析字段 |

### 3.1 DayPack 字段顺序

已确认当前 App 发出的 `DayPack` 字段顺序为：

```text
Year
Month
Day
DeviceMode
FocusChallengeEnabled
MorningGreeting
DailySummary
FirstItem
CurrentScheduleSummary
CompanionPhrase
TaskCount
TopTask[]:
  TaskId
  Title
  IsCompleted
  Priority
SettlementData:
  TasksCompleted
  TasksTotal
  PointsEarned(2BE)
  TotalFocusMinutes(2BE)
  FocusSessionCount
  LongestFocusMinutes(2BE)
  InterruptionCount
  SummaryMessage
  EncouragementMessage
```

确认点：`TopTask` 里没有旧的微行动字段。

### 3.2 TaskInPage 字段顺序

已确认当前 App 发出的 `TaskInPage` 字段顺序为：

```text
TaskId
TaskTitle
TaskDescription
Encouragement
FocusChallengeActive
```

确认点：没有旧的微行动说明/原因字段。

---

## 4. Device → App 模拟结果

Device → App 简单包格式：

```text
type(1) + length(1) + payload
```

这次模拟覆盖所有当前 App 认识的设备事件：

| Type | 名称 | 模拟结果 |
|---|---|---|
| `0x01` | `EncoderRotateUp` | 通过 |
| `0x02` | `EncoderRotateDown` | 通过 |
| `0x03` | `EncoderShortPress` | 通过 |
| `0x04` | `EncoderLongPress` | 通过 |
| `0x05` | `PowerShortPress` | 通过 |
| `0x06` | `PowerLongPress` | 通过 |
| `0x10` | `EnterTaskIn` | 通过 |
| `0x11` | `CompleteTask` | 通过 |
| `0x12` | `SkipTask` | 通过 |
| `0x13` | `SelectedTaskChanged` | 通过 |
| `0x14` | `WheelSelect` | 通过 |
| `0x15` | `ViewEventDetail` | 通过 |
| `0x16` | `ReminderAcknowledged` | 通过 |
| `0x17` | `ReminderDismissed` | 通过 |
| `0x20` | `RequestRefresh` | 通过 |
| `0x30` | `DeviceWake` | 通过 |
| `0x31` | `DeviceSleep` | 通过 |
| `0x40` | `LowBattery` | 通过 |

### 4.1 CompleteTask 样例

输入：任务 ID `task-ble-plan`，时间戳 `1767225600`。

```text
11 12
0D 74 61 73 6B 2D 62 6C 65 2D 70 6C 61 6E
69 55 B9 00
```

字段解释：

| 字节 | 含义 |
|---|---|
| `11` | `CompleteTask` |
| `12` | payload 长度 18 |
| `0D ...` | `task-ble-plan` |
| `69 55 B9 00` | Unix timestamp，大端 |

### 4.2 EventLogBatch 分包回传

已模拟设备用 9 字节分包回传 `EventLogBatch (0x21)`。

确认点：App 会先按 9 字节分包尝试组包，组包完成后才按业务事件解析，不会把分包误当成简单包。

批次样例内容：

```text
Count = 4
EncoderRotateUp
LowBattery(9)
CompleteTask(task-ble-plan, 1767225600)
ReminderDismissed(1767225601)
```

解析结果：4 条事件都能被 App 正确识别。

---

## 5. 安全包和开发显示命令

### 5.1 SecureEnvelope

已模拟 `BLE_SHARED_SECRET` 已配置时的安全包：

```text
外层 type = 0x7E
外层 payload = SecureEnvelope
SecureEnvelope 内层 payloadType = 真实业务 type
```

模拟结果：

| 项 | 结果 |
|---|---|
| 安全握手请求 | 通过 |
| 安全握手响应 | 通过 |
| `DeviceMode` 包装成 `SecureEnvelope` | 通过 |
| `SecureEnvelope` 解回真实 `DeviceMode` | 通过 |

第一轮真实硬件联调先不开 `BLE_SHARED_SECRET`，先跑明文开发模式。明文协议跑通后，再切到安全模式。

### 5.2 开发显示命令

当前 `sendDisplayScene` / `sendScreensaverConfig` 不是标准 BLEDataType 包，而是开发显示命令：

```text
AA 01 01 SceneId
AA 01 02 Type SceneId PostcardDay QuoteLen Quote AuthorLen Author
```

模拟结果：

| 命令 | 样例 | 结果 |
|---|---|---|
| `DisplayScene(forest)` | `AA 01 01 01` | 通过 |
| `ScreensaverConfig(postcard, nightCity)` | `AA 01 02 01 02 07 ...` | 通过 |
| 开发显示命令误走标准包解析 | `AA...` | 被拒绝 |

硬件如果只做第一轮 bring-up，可以先支持 `0xAA` 开发命令。要做正式协议，建议后续分配标准 `BLEDataType`。

---

## 6. 坏包模拟结果

| 场景 | 模拟结果 | 说明 |
|---|---|---|
| 简单包 length 比实际 payload 大 | 拒绝 | 避免半包被误解析 |
| 9 字节分包 CRC 错误 | 拒绝 | 避免坏分包进入组包缓存 |
| 开发显示命令走标准包解析 | 拒绝 | `0xAA` 必须单独处理 |
| EventLogBatch 大包 | 通过 | 先分包组包，再业务解析 |

---

## 7. 给硬件团队的实现要求

以下不是待确认项，而是 App 当前真实 BLE 协议。硬件团队第一版固件按这些实现：

1. App → Device 标准包长度是 2 字节大端；Device → App 简单包长度是 1 字节。
2. 9 字节分包的 CRC16 是 CRC16-CCITT-FALSE，校验对象只包含本分包 payload。
3. `Weather.Condition` 现在发的是 `sun.max.fill` / `cloud.rain.fill` 这类字符串，不是 `sunny` / `rainy`。
4. `PetStatus` 字段顺序：`Name`（长度前缀）→ `Mood`（1字节 ASCII）→ `CharacterId`（长度前缀）。无 Stage / Progress 字节。
5. `PetStatus.CharacterId` 必须支持 `joy` / `silas` / `nova`。
6. `DayPack.TopTask` 和 `TaskInPage` 已经没有微行动字段。
7. 第一轮固件支持 `0xAA` 开发显示命令，并单独解析，不要按标准包解析。
8. 第一轮固件先支持明文开发模式。安全模式等明文协议跑通后再接。

---

## 8. 本地验证命令

```bash
cd /Users/demon/vibecoding/outku3/KirolePackage
swift test --filter BLEProtocolSimulationTests
swift test --filter BLEProtocolTests
swift test --filter BLESecurityTests
```

当前报告对应的新增模拟测试：

```text
BLEProtocolSimulationTests: 8 tests passed
```

# Kirole 专注状态重连与完整日程 App 对接说明

> 协议版本：Ver 1.3.0（语义底稿）  
> 已由 Ver 1.3.1 覆盖：`docs/专注状态重连协议变更_Ver_1_3_1.md`  
> 现行字节表：`docs/Kirole_BLE协议命令字节表_专注重连协议更新_Ver_1_3_1.md`  
> 仓库回写：`docs/BLE通信协议规格文档-v2.13.2补记.md`  
> 剩余协商项：`docs/专注重连-与硬件协商项_Ver_1_3_1.md`  



## 1. 主要变更

BLE 断连期间，设备按键触发的进入/退出专注会立即在设备本地生效，不等待 App 确认。

重连后，App 必须先接收设备专注快照和离线操作，完成幂等处理与状态裁决，再恢复普通 `FocusStatus` 下发。

新增 `Schedule（0x03）v2`：一次下发日期与完整日程事件，每条事件包含开始时间、标题、非空描述、分类、结束时间和辅助文案。Schedule 与 DayPack 的日程可见字段完全相同时不替换；任一可见字段不同时，由完整 Schedule 替换日程与日期字段，DayPack 其他字段保持不变。

## 2. 核心规则

1. 断连状态下，只有设备有效按键可以改变设备专注状态。
2. 设备操作立即生效，同时写入离线等待队列。
3. App 不得用断连前缓存的 `idle` 或旧 `active` 状态覆盖设备。
4. 离线操作按 `OperationID` 去重，同一个操作只能执行一次。
5. 专注进入、退出、计时和结算都必须绑定同一个 `FocusSessionId`。
6. 同一会话发生 `active/end` 冲突时，结束优先。
7. 设备与 App 的计时差值在 120 秒以内视为正常，不需要新建会话。
8. `Phase` 和 `Bottles` 根据最终权威时长重新计算，禁止把设备值和 App 值相加。
9. Schedule v2 的 `Description` 必须非空；App 不得只发送标题和开始时间。
10. Schedule 与 DayPack 的日期、事件数量、事件顺序及全部可见字段完全相同时不替换、不刷新；任一字段不同时，由完整 Schedule 原子替换日程与日期字段。

## 3. App 本次需要完成的改动

| 序号 | 改动 | App 侧要求 |
|---|---|---|
| 1 | 识别待同步状态 | 解析 `OfflineSync STATE` 中的 `PendingCount` 和 `FocusSyncPending(bit4)` |
| 2 | 接收设备专注快照 | 新增解析 `FOCUS_STATE（0x25 / 0x83）` |
| 3 | 回放离线操作 | 按 `OperationID` 顺序、幂等处理 `OP_BATCH` 中的专注操作 |
| 4 | 返回处理结果 | 连续处理成功后发送 `OP_ACK`，并下发 `FOCUS_RESOLVE` |
| 5 | 升级普通状态同步 | `FocusStatus（0x14）` 升级为 `SubVersion 0x02` |
| 6 | 完善专注数据模型 | 增加 `FocusSessionId`、`FocusRevision` 和操作去重账本 |
| 7 | 升级完整日程同步 | `Schedule（0x03）` 使用 `SubVersion 0x02`，发送日期与完整六字段 Event；按可见字段比较后决定是否替换 DayPack 日程 |

## 4. 重连同步顺序

```text
DeviceWake
    ↓
OfflineSync STATE
    ↓
FOCUS_STATE
    ↓
OP_BATCH
    ↓
OP_ACK + FOCUS_RESOLVE
    ↓
普通 FocusStatus / TaskInPage / DayPack / Schedule
```

### App 处理步骤

1. 收到 `DeviceWake`，建立本次连接上下文。
2. 立即进入专注同步锁定状态，例如 `focusSyncLocked = true`。
3. 解析 `STATE`：
   - 检查 `PendingCount`。
   - 检查 `FocusSyncPending(bit4)`。
4. 接收 `FOCUS_STATE`，建立设备当前专注状态快照。
5. 如果 `PendingCount > 0`，按 `OperationID` 递增处理 `OP_BATCH`。
6. 仅在连续操作处理成功后，发送：
   - `OP_ACK`：确认连续成功处理到的最大 `OperationID`。
   - `FOCUS_RESOLVE`：下发最终专注状态、时间和版本。
7. 设备确认裁决成功且双方版本一致后，解除同步锁定。
8. 恢复普通 `FocusStatus`、`TaskInPage`、`DayPack` 和 `Schedule` 同步。

### 重连阶段禁止事项

- 不要在收到 `DeviceWake` 后立即发送旧的 `FocusStatus`。
- 不要用 App 的旧 `idle` 覆盖设备的离线 `active`。
- 不要越过处理失败的操作继续累计 ACK。
- 不要在裁决成功前要求设备删除离线队列。
- 不要使用 `DeviceMode（0x12）` 进入、退出或裁决专注状态；它只是设置快照。

## 5. 消息变更总览

| 方向 | Type / Opcode | 消息 | Payload | 用途 |
|---|---|---|---:|---|
| Device → App | `0x25 / 0x83` | `FOCUS_STATE` | `37+N` | 重连时上报设备当前或待裁决的专注快照 |
| Device → App | `0x25 / 0x82` | `OP_BATCH` | 变长 | 补报离线产生的进入、完成或跳过操作 |
| App → Device | `0x25 / 0x05` | `OP_ACK` | `9` | 确认连续成功处理到的最大操作 ID |
| App → Device | `0x25 / 0x06` | `FOCUS_RESOLVE` | `33` | 下发最终裁决和权威时间、版本 |
| App → Device | `0x14 v2` | `FocusStatus` | `25+N` | 裁决完成后的权威专注状态 |
| App → Device | `0x03 v2` | `Schedule` | `5 + Σ(6+T+N+D+E+S)` | 完整日期与日程快照，补齐标题、描述、分类、结束时间和辅助文案 |
| Device → App | `0x10 v2` | `EnterTaskIn` | `18+N` | 进入专注 |
| Device → App | `0x11 v2` | `CompleteTask` | `22+N` | 完成任务并退出专注 |
| Device → App | `0x12 v2` | `SkipTask` | `22+N` | 跳过任务并退出专注 |

所有多字节整数均使用 **Big Endian**。

## 6. 关键字段

### 6.1 幂等与会话标识

| 字段 | 说明 |
|---|---|
| `BootSessionId` | 设备启动会话 ID，4 字节 |
| `OperationID` | 单次设备操作 ID，4 字节、非零；重传必须复用原值 |
| `FocusSessionId` | 8 字节原始值：`BootSessionId(4B) + StartOperationID(4B)` |
| 操作幂等键 | `DeviceId + BootSessionId + OperationID` |
| `FocusRevision` | 权威专注状态版本，状态变化时严格递增 |

App 必须用 `FocusSessionId` 绑定同一次专注的进入、退出、计时、页面状态和结算记录。

### 6.2 状态枚举

| 值 | 名称 | 含义 |
|---|---|---|
| `0x00` | `idle` | 无活动专注会话 |
| `0x01` | `active` | 会话正在计时 |
| `0x02` | `endedPending` | 设备已结束，但结束操作尚未完成裁决 |

### 6.3 开始来源

| 值 | 名称 | 时间规则 |
|---|---|---|
| `0x00` | `appEstablished` | 会话在线建立，重连后继续使用 App 原开始时间 |
| `0x01` | `deviceOffline` | 会话由设备离线建立，首次同步使用设备开始时间 |

### 6.4 结束原因

| 值 | 名称 | 含义 |
|---|---|---|
| `0x00` | `none` | 会话仍处于活动状态 |
| `0x01` | `complete` | 设备短按完成 |
| `0x02` | `skip` | 设备长按跳过 |
| `0x03` | `appEnd` | App 已结束会话 |

## 7. 新增消息字段

### 7.1 FOCUS_STATE

方向：Device → App  
Type：`0x25`  
Opcode：`0x83`  
Payload：`37+N` 字节

| 偏移 | 字段 | 大小 | 说明 |
|---|---|---:|---|
| `0` | Opcode | 1 | 固定 `0x83` |
| `1..4` | FocusRevision | 4 | 设备已应用版本，离线状态变化也会递增 |
| `5..8` | BootSessionId | 4 | 设备启动会话 ID |
| `9..16` | FocusSessionId | 8 | 当前或待裁决会话；无会话时全 0 |
| `17` | FocusState | 1 | `idle / active / endedPending` |
| `18` | StartSource | 1 | `appEstablished / deviceOffline` |
| `19` | TaskIdLength | 1 | `0..36` |
| `20..19+N` | TaskId | N | ASCII 任务 ID |
| `20+N..23+N` | StartTimestamp | 4 | Unix 秒；RTC 无效时为 0 |
| `24+N..27+N` | EndTimestamp | 4 | 活动会话为 0 |
| `28+N..31+N` | ElapsedSeconds | 4 | 设备累计秒数 |
| `32+N..35+N` | LastOperationID | 4 | 最近相关操作 ID |
| `36+N` | EndReason | 1 | `none / complete / skip / appEnd` |

App 收到该消息后必须继续保持同步锁定，不能立即下发普通 `FocusStatus`。

### 7.2 FOCUS_RESOLVE

方向：App → Device  
Type：`0x25`  
Opcode：`0x06`  
Payload：固定 33 字节

| 偏移 | 字段 | 大小 | App 填写规则 |
|---|---|---:|---|
| `0` | Opcode | 1 | 固定 `0x06` |
| `1..4` | ResolveID | 4 | 非零；重试复用原值 |
| `5..12` | FocusSessionId | 8 | 最终会话 ID；无目标会话时可全 0 |
| `13` | FocusState | 1 | 最终状态 |
| `14` | ResolveResult | 1 | 裁决结果 |
| `15..18` | StartTimestamp | 4 | 权威开始时间 |
| `19..22` | EndTimestamp | 4 | 权威结束时间；活动会话为 0 |
| `23..26` | ElapsedSeconds | 4 | 权威累计秒数 |
| `27..30` | FocusRevision | 4 | 裁决后的权威版本 |
| `31` | Phase | 1 | 根据权威时长计算 |
| `32` | Bottles | 1 | 根据权威时长计算，不累加双方值 |

`ResolveResult`：

| 值 | 名称 | 处理结果 |
|---|---|---|
| `0x00` | `accepted` | 接受设备状态 |
| `0x01` | `closed` | 结束优先，会话已关闭 |
| `0x02` | `conflictResolved` | 不同活动会话已归并 |
| `0x03` | `rejected` | 载荷或会话关系非法，设备保留队列 |
| `0xFF` | `internalError` | App 内部错误，设备保留并重试 |

## 8. 已有消息 v2 改动

### 8.1 FocusStatus（0x14，App → Device）

新增/调整字段：

```text
SubVersion(1) = 0x02
FocusRevision(4)
FocusSessionId(8)
FocusState(1)
Phase(1)
Bottles(1)
ElapsedSeconds(4)
TaskTitleLength(1) + TaskTitle(N，N≤40)
SegmentSeconds(4)
```

Payload 总长：`25+N`。

要求：

- 只能在重连裁决完成后发送。
- `FocusRevision` 小于设备已应用版本时，设备应拒绝该状态。
- `idle` 状态下 `FocusSessionId` 全 0，标题长度为 0。

### 8.2 EnterTaskIn（0x10，Device → App）

```text
SubVersion(1) = 0x02
OperationID(4)
FocusSessionId(8)
TaskIdLength(1) + TaskId(N，N≤36)
StartTimestamp(4)
```

Payload 总长：`18+N`。

### 8.3 CompleteTask / SkipTask（0x11 / 0x12，Device → App）

```text
SubVersion(1) = 0x02
OperationID(4)
FocusSessionId(8)
TaskIdLength(1) + TaskId(N，N≤36)
EndTimestamp(4)
ElapsedSeconds(4)
```

Payload 总长：`22+N`。

事件 Type 隐含结束原因：

- `0x11`：`complete`
- `0x12`：`skip`

## 9. 状态冲突裁决

| 设备状态 | App 状态 | 最终结果 | 时间来源 | 页面与结算 |
|---|---|---|---|---|
| 离线新进入并保持 active | idle | 接受设备会话 | 设备 start | App 开启专注 UI |
| 离线进入后又退出 | idle | 生成一次历史会话 | 设备 start/end | 不闪开专注 UI，只结算一次 |
| 同一会话 active | 同一会话 active | 保持原会话 | App 原 start | 不重建、不重发 start |
| 设备已 end | 同一会话 active | 结束优先 | 设备 end | App 撤专注 UI 并结算一次 |
| 设备 active | 同一会话已 end | 结束优先 | App end | 设备退出并停止计时 |
| 双方都 end | 同一会话已 end | 保持结束 | 较早的有效 end | 去重后只结算一次 |
| 设备 active，会话 ID 不同 | App 存在另一 active | 设备待同步 Start 优先 | 设备 start | 关闭旧 App 会话并记录冲突日志 |

## 10. 时间、ACK 与可靠性

### 时间

- 协议统一使用秒，不使用分钟进行重连裁决。
- 计时差值 `≤120 秒`：按正常误差处理。
- 计时差值 `>120 秒`：记录异常，但不要因此创建新会话。
- `StartSource=appEstablished`：使用 App 原开始时间。
- `StartSource=deviceOffline`：使用设备开始时间。

### ACK

- `OP_ACK` 只确认连续成功处理的最大 `OperationID`。
- 遇到缺口或失败记录时停止推进 ACK。
- 不允许部分失败后越级确认后面的操作。

### 幂等

- App 保存操作去重账本：`DeviceId + BootSessionId + OperationID`。
- 重复收到相同操作时返回已有结果，不重复创建专注、退出或结算。
- 重试必须复用原 `OperationID`、`ResolveID` 和原始 payload。

### 异常恢复

- `ResolveResult=rejected/internalError`：设备保留队列，App 修复后重试。
- `STATE` 出现 `OperationOverflow + NeedsFullSync`：执行完整状态核对。
- 任何异常都不能静默丢弃设备离线操作。

## 11. 建议的 App 最小数据模型

```text
FocusSession {
    deviceId
    bootSessionId
    focusSessionId
    taskId
    state
    startSource
    startTimestamp
    endTimestamp
    elapsedSeconds
    focusRevision
    lastOperationId
}

OperationLedgerKey = deviceId + bootSessionId + operationId
```

## 12. Schedule v2（0x03）完整日程

### 12.1 Payload 总体结构

方向：App → Device  
Type：`0x03`  
SubVersion：`0x02`  
Payload：`5 + Σ(6+T+N+D+E+S)` 字节

```text
SubVersion(0x02) + Year + Month + Day + EventCount + Events[]
```

| 偏移 | 字段 | 大小 | App 填写规则 |
|---|---|---:|---|
| `0` | SubVersion | 1 | 固定 `0x02` |
| `1` | Year | 1 | 公历年份减 2000，取值 `0–99` |
| `2` | Month | 1 | `1–12` |
| `3` | Day | 1 | 必须与 Year、Month 组成有效日期 |
| `4` | EventCount | 1 | `0–8`，必须与后续 Event 数量一致 |
| `5..` | Events[] | 变长 | 连续编码 EventCount 条完整 Event |

设备必须在完整解析、校验全部 Event 且确认无剩余字节后原子应用整条 Schedule；任何字段非法时拒绝整包并保留当前日程。

### 12.2 Event 字段顺序

```text
Time + Title + Description + Category + EndTime + SupportText
```

| 顺序 | 字段 | 编码 | 长度 / 枚举 | 是否可空 | 规则 |
|---:|---|---|---|---|---|
| 1 | Time | `Length(1) + UTF-8(T)` | `T=0` 或 `T=5` | 全天事件可空 | 非空时必须为 `HH:mm` |
| 2 | Title | `Length(1) + UTF-8(N)` | `1≤N≤40` | 不可空 | 日程标题 |
| 3 | Description | `Length(1) + UTF-8(D)` | `1≤D≤120` | 不可空 | 可见日程描述，禁止只发送标题 |
| 4 | Category | `uint8` | `0x00–0x06` | 不可空 | 超范围拒绝整包 |
| 5 | EndTime | `Length(1) + UTF-8(E)` | `E=0` 或 `E=5` | 全天事件可空 | 定时事件必须晚于 Time |
| 6 | SupportText | `Length(1) + UTF-8(S)` | `0≤S≤120` | 可空 | 空字符串编码为 `0x00` |

每条 Event 长度为：

```text
6 + T + N + D + E + S
```

其中 6 字节分别是 Time、Title、Description、EndTime、SupportText 的 5 个长度字节以及 1 字节 Category。

时间规则：

- 定时事件的 Time 与 EndTime 都必须是 5 字节 `HH:mm`，且 EndTime 晚于 Time。
- 全天事件必须同时使用 `TimeLength=0` 和 `EndTimeLength=0`。
- Ver 1.3.0 不支持跨午夜事件；App 应拆分为两个日期内事件或不发送。

### 12.3 简单包与 11 字节分包

Payload 较小时可直接发送简单包：

```text
Type(0x03, 1B) + PayloadLength(2B, BE) + 完整 Schedule Payload
```

Payload 较大时可沿用现有 11 字节分包：

```text
Type(1) + MessageId(2) + Seq(2) + Total(2) + PayloadLen(2) + CRC16(2) + 分片 Payload
```

要求：

- 同一消息的所有分包使用相同 `MessageId`。
- `Seq` 从 0 开始；重发必须从 `Seq=0` 整条重发。
- 每片 CRC 使用 CRC16-CCITT-FALSE：poly `0x1021`、init `0xFFFF`、xorout `0x0000`、reflect in/out false。
- 设备先完成重组，再按同一套 Schedule v2 规则校验和应用；简单包与分包的业务结果必须一致。
- 旧版 `EventCount + Title + StartTime` 简化 Schedule 没有 `SubVersion=0x02`，必须严格拒绝，不做猜测、兼容解析或降级处理。

### 12.4 与 DayPack 的比较和覆盖规则

可见字段比较范围：

- 日期：Year、Month、Day。
- 事件数量与事件顺序。
- 每条事件的 Time、Title、Description、Category、EndTime、SupportText。

处理规则：

| 条件 | 设备处理 | 日程显示 | DayPack 其他字段 |
|---|---|---|---|
| 全部可见字段完全相同 | 不替换、不触发刷新 | 保持当前内容 | 保持不变 |
| 任一可见字段不同 | 用完整 Schedule 原子替换日期与日程字段 | 显示 Schedule 的完整标题与描述 | PetDialogue、TopTasks、SettlementData、DaySummary、FirstUp 等保持不变 |

普通连接内，如果 DayPack 与 Schedule 均到达，完整 Schedule 对日程可见字段拥有最终优先级。不得用后到的旧 DayPack 覆盖已确认的 Schedule。

OfflineSync 的 `DatasetMask` 同时包含 `bit1 Schedule` 和 `bit2 DayPack` 时，固定按以下顺序提交：

```text
先应用 DayPack
    ↓
再比较并应用 Schedule
    ↓
Schedule 对日程可见字段最终优先，DayPack 其他字段保持
```

### 12.5 十六进制示例

#### 零事件：2026-08-18

```text
03 00 05 02 1A 08 12 00
```

解码：

- `03`：Type = Schedule。
- `00 05`：PayloadLength = 5。
- `02`：SubVersion = v2。
- `1A 08 12`：2026-08-18。
- `00`：EventCount = 0。

#### 单事件：2026-08-18

事件内容：

- Time：`09:00`
- Title：`Standup`
- Description：`Daily sync`
- Category：`0x02`
- EndTime：`09:30`
- SupportText：`Share blockers`

```text
03 00 34 02 1A 08 12 01 05 30 39 3A 30 30 07 53 74 61 6E 64 75 70 0A 44 61 69 6C 79 20 73 79 6E 63 02 05 30 39 3A 33 30 0E 53 68 61 72 65 20 62 6C 6F 63 6B 65 72 73
```

`00 34` 表示 PayloadLength = 52。事件字段按固定六字段顺序排列，解析结束后不得有剩余字节。

# Kirole BLE 通信协议规格文档

**版本:** v1.3.1
**更新日期:** 2026-02-12
**状态:** 草稿

---

## 目录

1. [协议概述](#1-协议概述)
2. [BLE 配置](#2-ble-配置)
3. [数据包格式](#3-数据包格式)
4. [App → Device 命令](#4-app--device-命令)
5. [Device → App 事件](#5-device--app-事件)
6. [页面数据结构](#6-页面数据结构)
7. [示例数据](#7-示例数据)
8. [错误处理](#8-错误处理)

---

## 1. 协议概述

### 1.1 用途

本文档定义了 Kirole iOS App 与 E-ink 硬件设备之间的 BLE 通信协议。该协议支持：

- 从 App 向设备发送每日数据（Day Pack）
- 从设备向 App 接收用户交互事件
- 实时任务状态同步

### 1.2 修订历史

| 版本 | 日期 | 变更内容 |
|---------|------------|----------------------------------|
| v1.0.0  | 2026-01-30 | 初始协议规格 |
| v1.1.0  | 2026-01-31 | 新增 WheelSelect、ViewEventDetail、LowBattery 事件 |
| v1.2.0  | 2026-02-12 | 新增 Spectra 6 像素格式、Encoder/Power 按钮事件文档 |
| v1.3.0  | 2026-02-12 | Message House：新增 SmartReminder (0x13) 命令、DayPack/TaskInPage 中的 microAction 字段、SettlementData 中的专注指标、ReminderAcknowledged/Dismissed 事件 |
| v1.3.1  | 2026-02-12 | 新增 Section 3.2 九字节分包格式；Spectra 6 部分新增交叉引用至硬件需求文档 |

### 1.3 术语表

| 术语 | 定义 |
|---------------|------------------------------------------------------|
| Day Pack      | 发送至设备的完整每日数据包 |
| Event Log     | 从设备发送至 App 的用户交互事件 |
| Task In       | E-ink 显示屏上的任务详情页 |
| Settlement    | 每日结算总结页 |
| Focus Mode    | 减少干扰的简化显示模式 |
| Encoder Knob  | 带按压按钮的旋转编码器，用于导航 |

---

## 2. BLE 配置

### 2.1 Service UUID

```
Service UUID: 0000FFE0-0000-1000-8000-00805F9B34FB
```

### 2.2 Characteristics

| Characteristic | UUID                                   | 方向 | 属性 |
|----------------|----------------------------------------|----------------|-----------------|
| Write          | `0000FFE1-0000-1000-8000-00805F9B34FB` | App → Device   | Write           |
| Notify         | `0000FFE2-0000-1000-8000-00805F9B34FB` | Device → App   | Notify          |

### 2.3 连接参数

| 参数 | 值 |
|--------------------|------------|
| Scan Timeout       | 10 秒 |
| Connection Timeout | 15 秒 |
| 自动重连 | 启用 |

---

## 3. 数据包格式

### 3.1 通用数据包结构（App → Device）

所有从 App 发送至设备的数据遵循以下格式：

```
+--------+--------+--------+------------------+
| Type   | Length (BE)     | Payload          |
| 1 byte | 2 bytes         | N bytes          |
+--------+--------+--------+------------------+
```

| Field   | Size    | 描述 |
|---------|---------|------------------------------------------|
| Type    | 1 byte  | 命令类型标识符（见第 4 节） |
| Length  | 2 bytes | Payload 长度（Big Endian） |
| Payload | N bytes | 命令特定数据 |

### 3.2 分包格式（大 Payload）

当 payload 超过 BLE MTU 时，使用 9 字节头部将其拆分为多个分包：

```
+--------+------------+------+-------+------------+----------+------------------+
| Type   | MessageId  | Seq  | Total | PayloadLen | CRC16    | Payload          |
| 1 byte | 2 bytes BE | 1 B  | 1 B   | 2 bytes BE | 2 bytes  | N bytes          |
+--------+------------+------+-------+------------+----------+------------------+
```

| Field      | Size    | 描述 |
|------------|---------|------------------------------------------------------|
| Type       | 1 byte  | 命令类型标识符（同 Section 3.1） |
| MessageId  | 2 bytes | 消息标识符（Big Endian），同一消息的所有分包共享 |
| Seq        | 1 byte  | 分包序号（从 0 开始） |
| Total      | 1 byte  | 分包总数 |
| PayloadLen | 2 bytes | 本分包的 payload 长度（Big Endian） |
| CRC16      | 2 bytes | 本分包 payload 的 CRC16-CCITT-FALSE 校验值（Big Endian） |
| Payload    | N bytes | 分包 payload 数据 |

**头部大小：** 共 9 字节

**CRC16 参数：**
- 算法：CRC16-CCITT-FALSE
- 多项式：`0x1021`
- 初始值：`0xFFFF`
- XOR out：`0x0000`
- Reflect in/out：`false`

**重组：** 接收端收集所有相同 MessageId 的分包，按 Seq 排序，验证每个分包的 CRC16，然后拼接 payload 以重建完整消息。

**使用场景：** DayPack (0x10)、TaskInPage (0x11) 及其他大 payload 使用此格式。简单命令（PetStatus、Weather、Time）使用 Section 3.1 的 3 字节头部。

### 3.3 字符串编码

字符串使用长度前缀编码：

```
+--------+------------------+
| Length | UTF-8 Data       |
| 1 byte | N bytes          |
+--------+------------------+
```

- **编码方式：** UTF-8
- **最大长度：** 按字段指定（超出则截断）
- **Length 字节：** 实际字节数（非字符数）

### 3.4 字节序

- **多字节整数：** Big Endian
- **有符号整数：** 二进制补码

---

## 4. App → Device 命令

### 4.1 命令类型汇总

| Type   | Name         | 描述 |
|--------|--------------|-----------------------------------|
| `0x01` | PetStatus    | 宠物状态信息 |
| `0x02` | TaskList     | 今日任务列表 |
| `0x03` | Schedule     | 今日日历事件 |
| `0x04` | Weather      | 当前天气信息 |
| `0x05` | Time         | 当前时间同步 |
| `0x10` | DayPack      | 完整每日数据包 |
| `0x11` | TaskInPage   | 任务详情页数据 |
| `0x12` | DeviceMode   | 设备运行模式 |
| `0x13` | SmartReminder| AI 智能提醒推送 |
| `0x20` | EventLogRequest | 请求指定时间戳之后的事件日志 |

---

### 4.2 PetStatus (0x01)

用于显示的宠物状态信息。

**Payload 结构：**

| Offset | Field    | Size        | Max Length | 描述 |
|--------|----------|-------------|------------|--------------------------------|
| 0      | Name     | 1 + N bytes | 20 chars   | 宠物名称（长度前缀） |
| N+1    | Mood     | 1 byte      | -          | 心情首字母 ASCII |
| N+2    | Stage    | 1 byte      | -          | 成长阶段首字母 ASCII |
| N+3    | Progress | 1 byte      | -          | 进度 0-100（上限 255） |

**Mood 值：**

| Value | Mood        |
|-------|-------------|
| `H`   | Happy       |
| `E`   | Excited     |
| `F`   | Focused     |
| `S`   | Sleepy      |
| `M`   | Missing You |

**Stage 值：**

| Value | Stage  |
|-------|--------|
| `B`   | Baby   |
| `C`   | Child  |
| `T`   | Teen   |
| `A`   | Adult  |
| `E`   | Elder  |

---

### 4.3 TaskList (0x02)

今日任务列表（最多 10 个任务）。

**Payload 结构：**

| Offset | Field      | Size        | 描述 |
|--------|------------|-------------|--------------------------------|
| 0      | TaskCount  | 1 byte      | 任务数量（0-10） |
| 1+     | Tasks[]    | Variable    | 任务条目数组 |

**Task 条目：**

| Offset | Field       | Size        | Max Length | 描述 |
|--------|-------------|-------------|------------|--------------------------|
| 0      | Title       | 1 + N bytes | 30 chars   | 任务标题 |
| N+1    | IsCompleted | 1 byte      | -          | 0x00=未完成, 0x01=已完成 |

---

### 4.4 Schedule (0x03)

今日日历事件（最多 8 个事件）。

**Payload 结构：**

| Offset | Field       | Size        | 描述 |
|--------|-------------|-------------|--------------------------------|
| 0      | EventCount  | 1 byte      | 事件数量（0-8） |
| 1+     | Events[]    | Variable    | 事件条目数组 |

**Event 条目：**

| Offset | Field     | Size        | Max Length | 描述 |
|--------|-----------|-------------|------------|--------------------------|
| 0      | Title     | 1 + N bytes | 25 chars   | 事件标题 |
| N+1    | StartTime | 5 bytes     | -          | "HH:mm" 格式（原始 UTF-8） |

---

### 4.5 Weather (0x04)

当前天气信息。

**Payload 结构：**

| Offset | Field       | Size        | Max Length | 描述 |
|--------|-------------|-------------|------------|--------------------------|
| 0      | Temperature | 1 byte      | -          | 有符号 int8（摄氏度） |
| 1      | Condition   | 1 + N bytes | 15 chars   | 天气状况字符串 |

**Condition 值：**

| Value     | 描述 |
|-----------|-------------|
| `sunny`   | 晴天 |
| `cloudy`  | 多云 |
| `rainy`   | 雨天 |
| `snowy`   | 雪天 |
| `stormy`  | 暴风雨 |

---

### 4.6 Time (0x05)

时间同步。

**Payload 结构：**

| Offset | Field  | Size   | 描述 |
|--------|--------|--------|--------------------------------|
| 0      | Year   | 1 byte | 年份 - 2000（例如 26 = 2026） |
| 1      | Month  | 1 byte | 月份（1-12） |
| 2      | Day    | 1 byte | 日期（1-31） |
| 3      | Hour   | 1 byte | 小时（0-23） |
| 4      | Minute | 1 byte | 分钟（0-59） |
| 5      | Second | 1 byte | 秒（0-59） |

---

### 4.7 DayPack (0x10)

包含全部 4 个页面的完整每日数据包。

**Payload 结构：**

| Offset | Field                  | Size        | Max Length | 描述 |
|--------|------------------------|-------------|------------|--------------------------------|
| 0      | Year                   | 1 byte      | -          | 年份 - 2000 |
| 1      | Month                  | 1 byte      | -          | 月份（1-12） |
| 2      | Day                    | 1 byte      | -          | 日期（1-31） |
| 3      | DeviceMode             | 1 byte      | -          | 0x00=Interactive, 0x01=Focus |
| 4      | FocusChallengeEnabled  | 1 byte      | -          | 0x00=禁用, 0x01=启用 |
| 5      | MorningGreeting        | 1 + N bytes | 50 chars   | 页面 1：早安问候 |
| N+6    | DailySummary           | 1 + N bytes | 60 chars   | 页面 1：每日摘要 |
| ...    | FirstItem              | 1 + N bytes | 40 chars   | 页面 1：首个任务/事件 |
| ...    | CurrentScheduleSummary | 1 + N bytes | 30 chars   | 页面 2：日程摘要 |
| ...    | CompanionPhrase        | 1 + N bytes | 40 chars   | 页面 2：伴侣消息 |
| ...    | TaskCount              | 1 byte      | -          | 置顶任务数量（0-5，取决于屏幕尺寸） |
| ...    | TopTasks[]             | Variable    | -          | 页面 2：4寸最多 3 条，7.3寸最多 5 条 |
| ...    | SettlementData         | Variable    | -          | 页面 4：结算数据 |

**TopTask 条目：**

| Offset | Field          | Size        | Max Length | 描述 |
|--------|----------------|-------------|------------|--------------------------|
| 0      | TaskId         | 1 + N bytes | 36 chars   | UUID 字符串 |
| N+1    | Title          | 1 + N bytes | 30 chars   | 任务标题 |
| ...    | MicroActionWhat| 1 + N bytes | 40 chars   | 微行动文本（无则为空字符串） |
| ...    | IsCompleted    | 1 byte      | -          | 0x00=未完成, 0x01=已完成 |
| ...    | Priority       | 1 byte      | -          | 优先级（1-3） |

**SettlementData：**

| Offset | Field               | Size        | Max Length | 描述 |
|--------|---------------------|-------------|------------|--------------------------|
| 0      | TasksCompleted      | 1 byte      | -          | 已完成任务数 |
| 1      | TasksTotal          | 1 byte      | -          | 总任务数 |
| 2      | PointsEarned        | 2 bytes     | -          | 积分（Big Endian） |
| 4      | StreakDays          | 1 byte      | -          | 当前连续天数 |
| 5      | TotalFocusMinutes   | 2 bytes     | -          | 总专注时间（分钟，Big Endian） |
| 7      | FocusSessionCount   | 1 byte      | -          | 专注会话次数 |
| 8      | LongestFocusMinutes | 2 bytes     | -          | 最长单次专注时间（分钟，BE） |
| 10     | InterruptionCount   | 1 byte      | -          | 专注期间手机解锁次数 |
| 11     | SummaryMessage      | 1 + N bytes | 50 chars   | 总结文本 |
| N+12   | EncouragementMessage| 1 + N bytes | 50 chars   | 鼓励文本 |

---

### 4.8 TaskInPage (0x11)

任务详情页数据（页面 3）。

**Payload 结构：**

| Offset | Field                | Size        | Max Length | 描述 |
|--------|----------------------|-------------|------------|--------------------------|
| 0      | TaskId               | 1 + N bytes | 36 chars   | UUID 字符串 |
| N+1    | TaskTitle            | 1 + N bytes | 40 chars   | 任务标题 |
| ...    | MicroActionWhat      | 1 + N bytes | 40 chars   | 微行动：做什么（无则为空） |
| ...    | MicroActionWhy       | 1 + N bytes | 60 chars   | 动机锚点：为什么做（无则为空） |
| ...    | TaskDescription      | 1 + N bytes | 100 chars  | 任务描述 |
| ...    | EstimatedDuration    | 1 + N bytes | 10 chars   | 预估时长（例如 "30min"） |
| ...    | Encouragement        | 1 + N bytes | 50 chars   | 鼓励消息 |
| ...    | FocusChallengeActive | 1 byte      | -          | 0x00=未激活, 0x01=已激活 |

---

### 4.9 DeviceMode (0x12)

设置设备运行模式。

**Payload 结构：**

| Offset | Field | Size   | 描述 |
|--------|-------|--------|--------------------------------|
| 0      | Mode  | 1 byte | 0x00=Interactive, 0x01=Focus |

---

### 4.10 SmartReminder (0x13)

AI 智能提醒，从 App 推送至设备。

**Payload 结构：**

| Offset | Field        | Size        | Max Length | 描述 |
|--------|--------------|-------------|------------|--------------------------------------|
| 0      | ReminderText | 1 + N bytes | 60 chars   | 提醒消息文本 |
| N+1    | ReminderType | 1 byte      | -          | 0x00=gentle, 0x01=urgent, 0x02=streak_protect |
| N+2    | PetMoodByte  | 1 byte      | -          | 显示用宠物心情（ASCII: H/E/F/S/M） |

**ReminderType 值：**

| Value  | Name          | 描述 |
|--------|---------------|------------------------------------------|
| `0x00` | Gentle        | 普通提醒，标准显示 |
| `0x01` | Urgent        | 紧急提醒，加粗边框显示 |
| `0x02` | StreakProtect  | 连续天数保护，宠物显示担忧心情 |

**设备行为：**
- 在当前页面上显示横幅覆盖层
- 无用户交互时 10 秒后自动消失
- 任意按钮按下立即消失
- 向 App 发送 ReminderAcknowledged (0x16) 或 ReminderDismissed (0x17) 事件

---

### 4.11 EventLogRequest (0x20)

App 请求设备回传增量 Event Log（用于断线重连后补齐事件）。

**Payload 结构：**

| Offset | Field | Size    | 描述 |
|--------|-------|---------|-------------------------------------------|
| 0      | Since | 4 bytes | Unix Timestamp（Big Endian，UInt32） |

**设备行为：**
- 查询本地环形缓冲中 `timestamp > Since` 的事件
- 按批次通过 EventLogBatch (0x21) 回传

---

## 5. Device → App 事件

事件通过 Notify characteristic 从设备发送至 App。

### 5.1 事件数据包结构

```
+--------+--------+------------------+
| Type   | Length | Payload          |
| 1 byte | 1 byte | N bytes          |
+--------+--------+------------------+
```

### 5.2 事件类型汇总

| Type   | Name                | 描述 |
|--------|---------------------|------------------------------------|
| `0x01` | EncoderRotateUp   | Encoder 旋钮向上旋转（顺时针） |
| `0x02` | EncoderRotateDown  | Encoder 旋钮向下旋转（逆时针） |
| `0x03` | EncoderShortPress  | Encoder 旋钮短按（确认） |
| `0x04` | EncoderLongPress   | Encoder 旋钮长按 |
| `0x05` | PowerShortPress    | 电源按钮短按 |
| `0x06` | PowerLongPress     | 电源按钮长按 |
| `0x10` | EnterTaskIn         | 用户进入任务详情页 |
| `0x11` | CompleteTask        | 用户标记任务为已完成 |
| `0x12` | SkipTask            | 用户跳过任务 |
| `0x13` | SelectedTaskChanged | 用户切换了选中的任务 |
| `0x14` | WheelSelect         | Encoder 旋钮按下（旋钮选择确认） |
| `0x15` | ViewEventDetail     | 用户查看日历事件详情 |
| `0x16` | ReminderAcknowledged| 用户确认了智能提醒 |
| `0x17` | ReminderDismissed   | 智能提醒自动消失（超时） |
| `0x20` | RequestRefresh      | 设备请求数据刷新 |
| `0x21` | EventLogBatch       | 批量回传事件日志 |
| `0x30` | DeviceWake          | 设备从睡眠中唤醒 |
| `0x31` | DeviceSleep         | 设备进入睡眠模式 |
| `0x40` | LowBattery          | 设备电量低通知 |

---

### 5.3 EnterTaskIn (0x10)

用户进入任务详情页（专注模式开始）。

**Payload：**

| Offset | Field  | Size        | 描述 |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId 长度 |
| 1      | TaskId | N bytes     | UUID 字符串（UTF-8） |
| 1+N    | Timestamp | 4 bytes  | Unix Timestamp（Big Endian）（UInt32） |

**App 响应：**
- 发送 TaskInPage (0x11) 包含任务详情
- 记录该任务的专注会话开始时间戳

**专注时间追踪：**
此事件标记专注会话的开始。App 记录提供的时间戳，在收到 CompleteTask 或 SkipTask 时计算专注时长。

---

### 5.4 CompleteTask (0x11)

用户在设备上标记任务为已完成（短按旋钮）。

**Payload：**

| Offset | Field  | Size        | 描述 |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId 长度 |
| 1      | TaskId | N bytes     | UUID 字符串（UTF-8） |
| 1+N    | Timestamp | 4 bytes  | Unix Timestamp（Big Endian）（UInt32） |

**App 响应：**
- 更新 AppState 中的任务状态，重新计算积分
- 记录专注会话结束时间戳
- 计算专注时长（结束 - 开始）
- 与 Screen Time 数据交叉比对以确定实际专注时间

---

### 5.5 SkipTask (0x12)

用户跳过任务（长按旋钮 >1 秒）。

**Payload：**

| Offset | Field  | Size        | 描述 |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId 长度 |
| 1      | TaskId | N bytes     | UUID 字符串（UTF-8） |
| 1+N    | Timestamp | 4 bytes  | Unix Timestamp（Big Endian）（UInt32） |

**App 响应：**
- 标记任务为已跳过，切换到下一个任务
- 记录专注会话结束时间戳
- 计算专注时长（结束 - 开始）
- 与 Screen Time 数据交叉比对以确定实际专注时间

---

### 5.6 SelectedTaskChanged (0x13)

用户在概览页切换了选中的任务。

**Payload：**

| Offset | Field  | Size        | 描述 |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId 长度 |
| 1      | TaskId | N bytes     | UUID 字符串（UTF-8） |

**App 响应：** 更新选中任务状态。

---

### 5.7 RequestRefresh (0x20)

设备请求从 App 获取最新数据。

**Payload：** 无（Length = 0）

**App 响应：** 发送更新后的 DayPack (0x10)。

---

### 5.8 DeviceWake (0x30)

设备从睡眠模式唤醒。

**Payload：** 无（Length = 0）

**App 响应：** 可选择同步时间并发送更新数据。

---

### 5.9 DeviceSleep (0x31)

设备正在进入睡眠模式。

**Payload：** 无（Length = 0）

**App 响应：** 无需响应。

---

### 5.10 WheelSelect (0x14)

用户通过 Encoder 旋钮按下确认选择。

**Payload：**

| Offset | Field  | Size        | 描述 |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | 选中项 ID 长度 |
| 1      | ItemId | N bytes     | 选中项 ID（UTF-8） |

**App 响应：**
- 若选中任务：发送 TaskInPage (0x11) 包含任务详情
- 若选中事件：发送事件详情数据

---

### 5.11 ViewEventDetail (0x15)

用户查看日历事件详情。

**Payload：**

| Offset | Field   | Size        | 描述 |
|--------|---------|-------------|--------------------------|
| 0      | Length  | 1 byte      | EventId 长度 |
| 1      | EventId | N bytes     | Event ID（UTF-8） |

**App 响应：** 无需响应（自动超时返回概览页）。

---

### 5.12 ReminderAcknowledged (0x16)

用户通过按下任意按钮确认了智能提醒。

**Payload：**

| Offset | Field     | Size    | 描述 |
|--------|-----------|---------|--------------------------------------|
| 0      | Timestamp | 4 bytes | Unix Timestamp（Big Endian）（UInt32） |

**App 响应：** 记录提醒确认，更新提醒分析数据。

---

### 5.13 ReminderDismissed (0x17)

智能提醒在 10 秒超时后自动消失。

**Payload：**

| Offset | Field     | Size    | 描述 |
|--------|-----------|---------|--------------------------------------|
| 0      | Timestamp | 4 bytes | Unix Timestamp（Big Endian）（UInt32） |

**App 响应：** 记录提醒消失，调整未来提醒时机。

---

### 5.14 LowBattery (0x40)

设备电量低。

**Payload：**

| Offset | Field        | Size   | 描述 |
|--------|--------------|--------|--------------------------|
| 0      | BatteryLevel | 1 byte | 电量百分比（0-100） |

**App 响应：** 向用户显示低电量通知。

---

### 5.15 EventLogBatch (0x21)

设备批量回传事件日志（通常响应 EventLogRequest）。

**Payload 结构：**

| Offset | Field | Size | 描述 |
|--------|-------|------|---------------------------------------------|
| 0      | Count | 1 byte | 本批次记录条数 |
| 1+     | Records | Variable | 顺序拼接的记录流 |

**Record 编码：** `eventType (1B) + eventPayload (NB)`，`eventPayload` 按各事件类型定义（见 5.3 ~ 5.14）。

**解析规则：**
- `0x01~0x06`, `0x20`, `0x30`, `0x31`：无 payload（记录总长 1B）
- `0x40`：`BatteryLevel`（记录总长 2B）
- `0x16`, `0x17`：`Timestamp(4B)`（记录总长 5B）
- `0x10~0x12`：`Length(1B)+TaskId(NB)+Timestamp(4B)`（记录总长 `2+N+4`）
- `0x13~0x15`：`Length(1B)+Id(NB)`（记录总长 `2+N`）

---

## 6. 页面数据结构

### 6.1 页面 1：每日开始

用户早晨首次与设备交互时显示。

**内容：**
- 早安问候（个性化）
- 每日摘要（天气、任务数、首个事件）
- 首项预览（下一个事件或置顶任务）

**数据来源：** DayPack 字段：
- `morningGreeting`
- `dailySummary`
- `firstItem`

---

### 6.2 页面 2：概览

显示今日概览的主仪表盘。

**内容：**
- 当前/下一个日程项
- 前 N 个任务及完成状态（4寸 3 条，7.3寸 5 条）
- 伴侣短语（鼓励语）

**数据来源：** DayPack 字段：
- `currentScheduleSummary`
- `topTasks[]`
- `companionPhrase`

---

### 6.3 页面 3：任务详情

用户选择任务时显示的任务详情页。

**内容：**
- 任务标题和描述
- 预估时长
- 鼓励消息
- 专注挑战指示器

**数据来源：** TaskInPage 命令 (0x11)

**触发条件：** 来自设备的 EnterTaskIn 事件 (0x10)

---

### 6.4 页面 4：每日结算

每日结算总结页。

**内容：**
- 已完成任务数 / 总任务数
- 今日获得积分
- 当前连续天数
- 总结消息
- 明日鼓励语

**数据来源：** DayPack.settlementData

---

## 7. 示例数据

### 7.1 DayPack 示例（Hex）

```
Command: 0x10 (DayPack)

Full Packet:
10 00 C8                              // Type=0x10, Length=200 (example)

Payload:
1A 01 1E                              // Date: 2026-01-30
00                                    // DeviceMode: Interactive
00                                    // FocusChallengeEnabled: false

// Page 1: Start of Day
0F 47 6F 6F 64 20 6D 6F 72 6E 69 6E 67 21 20 F0  // "Good morning! " (15 bytes)
1A 59 6F 75 20 68 61 76 65 20 35 20 74 61 73 6B  // "You have 5 task" (26 bytes)
73 20 74 6F 64 61 79 2E
0E 39 3A 30 30 20 54 65 61 6D 20 63 61 6C 6C     // "9:00 Team call" (14 bytes)

// Page 2: Overview
0C 4E 65 78 74 3A 20 31 30 3A 30 30              // "Next: 10:00" (12 bytes)
0F 4B 65 65 70 20 67 6F 69 6E 67 21 20 F0 9F 92  // "Keep going! " (15 bytes)

// Top Tasks (3 tasks)
03                                    // TaskCount: 3

// Task 1
24 61 62 63 64 65 66 67 68 2D 31 32 33 34 2D 35  // TaskId (36 bytes UUID)
36 37 38 2D 39 30 61 62 2D 63 64 65 66 67 68 69
6A 6B 6C 6D
0C 52 65 76 69 65 77 20 50 52 73                 // "Review PRs" (12 bytes)
00                                    // IsCompleted: false
01                                    // Priority: 1

// ... (Task 2, Task 3 similar)

// Page 4: Settlement
03                                    // TasksCompleted: 3
05                                    // TasksTotal: 5
00 32                                 // PointsEarned: 50 (Big Endian)
07                                    // StreakDays: 7
12 47 72 65 61 74 20 70 72 6F 67 72 65 73 73 21  // "Great progress!" (18 bytes)
0E 53 65 65 20 79 6F 75 20 74 6F 6D 6F 72 72 6F  // "See you tomorrow" (14 bytes)
77 21
```

### 7.2 Event Log 示例（Hex）

**CompleteTask 事件：**

```
11                                    // Type: CompleteTask
29                                    // Length: 41 bytes
24                                    // TaskId Length: 36 bytes
61 62 63 64 65 66 67 68 2D 31 32 33 34 2D 35 36  // TaskId UUID
37 38 2D 39 30 61 62 2D 63 64 65 66 67 68 69 6A
6B 6C 6D
67 A1 B2 C3                          // Timestamp (Unix, BE)
```

**RequestRefresh 事件：**

```
20                                    // Type: RequestRefresh
00                                    // Length: 0 (no payload)
```

### 7.3 时间同步示例（Hex）

```
Command: 0x05 (Time)

Full Packet:
05 00 06                              // Type=0x05, Length=6

Payload:
1A                                    // Year: 26 (2026)
01                                    // Month: 1
1E                                    // Day: 30
09                                    // Hour: 9
1E                                    // Minute: 30
00                                    // Second: 0
```

### 7.4 SmartReminder 示例（Hex）

```
Command: 0x13 (SmartReminder)

Full Packet:
13 00 22                              // Type=0x13, Length=34

Payload:
// ReminderText: "Time to review that proposal!" (30 bytes)
1E 54 69 6D 65 20 74 6F 20 72 65 76
69 65 77 20 74 68 61 74 20 70 72 6F
70 6F 73 61 6C 21

00                                    // ReminderType: 0x00 (Gentle)
48                                    // PetMoodByte: 'H' (Happy)
```

### 7.5 ReminderAcknowledged 事件示例（Hex）

```
Event: 0x16 (ReminderAcknowledged)

16 04                                 // Type=0x16, Length=4
67 A1 B2 C3                          // Timestamp: 1738670787 (Big Endian)
```

---

## 8. 错误处理

### 8.1 连接错误

| 错误 | App 行为 |
|------------------------|-------------------------------------------|
| 蓝牙关闭 | 显示"请开启蓝牙"提示 |
| 权限被拒绝 | 显示设置跳转引导 |
| 未找到设备 | 重试扫描，显示"未找到设备" |
| 连接超时 | 重试连接（最多 3 次） |
| 意外断开 | 若已启用则自动重连 |

### 8.2 数据校验

| 校验项 | 规则 |
|------------------------|-------------------------------------------|
| 字符串长度 | 截断至最大长度 |
| 整数溢出 | 限制在有效范围内 |
| 无效事件类型 | 忽略未知事件类型 |
| 格式错误的数据包 | 丢弃并记录错误 |

### 8.3 重试策略

| 操作 | 最大重试次数 | 退避间隔 |
|------------------------|-------------|------------------------|
| Scan                   | 3           | 2s, 4s, 8s             |
| Connect                | 3           | 1s, 2s, 4s             |
| Write                  | 2           | 500ms, 1s              |

---

## 9. 专注时间计算

### 9.1 概述

专注时间通过结合设备事件与手机屏幕活动数据来计算。目标是测量任务会话期间的实际专注工作时间。

### 9.2 数据来源

| 来源 | 数据 | 用途 |
|--------|------|---------|
| 设备事件 | EnterTaskIn、CompleteTask、SkipTask 时间戳 | 定义任务会话边界 |
| Screen Time API | 手机屏幕解锁/锁定事件 | 检测会话期间的手机使用 |

### 9.3 计算算法

```
Focus Session:
  Start: EnterTaskIn timestamp
  End: CompleteTask or SkipTask timestamp
  Duration: End - Start

Focus Time Calculation:
  1. Get all screen unlock events during the session
  2. For each 30-minute window without screen unlock:
     - Count as focus time
  3. Total Focus Time = Sum of all 30+ minute uninterrupted periods
```

### 9.4 示例

```
Task Session: 09:00 - 10:30 (90 minutes total)

Screen Activity:
  09:05 - Phone unlocked (5 min usage)
  09:45 - Phone unlocked (2 min usage)
  10:20 - Phone unlocked (1 min usage)

Focus Periods:
  09:10 - 09:45 = 35 min (>30 min, counts as focus)
  09:47 - 10:20 = 33 min (>30 min, counts as focus)

Total Focus Time: 68 minutes
```

### 9.5 App 实现说明

- 使用 `DeviceActivityMonitor` 框架（iOS 15+）获取屏幕时间数据
- 需要用户授权 Screen Time 访问权限
- 本地存储专注会话数据以支持离线计算
- 连接时将专注数据同步至云端

---

## 10. Spectra 6 像素数据格式

> **注意：** 屏幕硬件规格（分辨率、色彩技术）的权威来源为 `硬件需求文档-Hardware-Requirements-Document.md` Section 4。本节仅描述像素数据在 BLE 传输中的编码格式。

### 10.1 概述

E-ink 显示屏使用 E Ink Spectra 6 技术，支持 6 种颜色。像素数据采用 4bpp（每像素 4 位）格式编码，每字节打包 2 个像素。

### 10.2 颜色索引表

| Index | Color  | Hex  |
|-------|--------|------|
| 0x0   | Black  | 0x0  |
| 0x1   | White  | 0x1  |
| 0x2   | Yellow | 0x2  |
| 0x3   | Red    | 0x3  |
| 0x5   | Blue   | 0x5  |
| 0x6   | Green  | 0x6  |

注意：索引值 0x4、0x7-0xF 为保留值。

### 10.3 像素打包

每字节包含 2 个像素：

```
Byte layout: [pixel_even (high nibble)] [pixel_odd (low nibble)]
```

| Bits  | 内容 |
|-------|------------------|
| 7-4   | 偶数像素索引 |
| 3-0   | 奇数像素索引 |

示例：黑色像素后跟白色像素 = `0x01`

### 10.4 帧缓冲区大小

| 屏幕 | 分辨率 | 像素数 | 缓冲区大小 |
|---------|-----------|---------|-------------|
| 4 寸  | 400 x 600 | 240,000 | 120,000 bytes (117.2 KB) |
| 7.3 寸| 800 x 480 | 384,000 | 192,000 bytes (187.5 KB) |

公式：`bufferSize = width * height / 2`

---

## 附录 A：Swift 类型参考

### A.1 BLEDataType Enum

```swift
public enum BLEDataType: UInt8, Sendable {
    case petStatus = 0x01
    case taskList = 0x02
    case schedule = 0x03
    case weather = 0x04
    case time = 0x05
    case dayPack = 0x10
    case taskInPage = 0x11
    case deviceMode = 0x12
    case smartReminder = 0x13
    case eventLogRequest = 0x20
    case eventLogBatch = 0x21
}
```

### A.2 EventLogType Enum

```swift
public enum EventLogType: String, Codable, Sendable {
    case enterTaskIn = "enter_task_in"       // 0x10
    case completeTask = "complete_task"      // 0x11
    case skipTask = "skip_task"              // 0x12
    case selectedTaskChanged = "selected_task_changed"  // 0x13
    case wheelSelect = "wheel_select"        // 0x14
    case viewEventDetail = "view_event_detail"  // 0x15
    case reminderAcknowledged = "reminder_acknowledged"  // 0x16
    case reminderDismissed = "reminder_dismissed"  // 0x17
    case requestRefresh = "request_refresh"  // 0x20
    case deviceWake = "device_wake"          // 0x30
    case deviceSleep = "device_sleep"        // 0x31
    case lowBattery = "low_battery"          // 0x40
}
```

### A.3 DeviceMode Enum

```swift
public enum DeviceMode: String, Codable, Sendable {
    case interactive = "Interactive"  // 0x00
    case focus = "Focus"              // 0x01
}
```

---

## 关联文档

| 文档 | 版本 | 描述 |
|------|------|------|
| 硬件需求文档-Hardware-Requirements-Document.md | v0.3 | 硬件电气需求（SoC、显示、电源、电池） |
| 固件功能规格文档.md | v1.3.0 | 固件功能规格（页面设计、交互流程、宠物系统） |

---

## 联系方式

如有协议问题或需要澄清，请联系 Kirole 开发团队。

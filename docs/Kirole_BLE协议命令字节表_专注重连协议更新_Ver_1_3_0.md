# Kirole BLE 协议命令字节表（专注重连协议更新）

**协议版本:** Ver 1.3.0  
**来源:** `docs/Kirole_BLE协议命令字节表_专注重连协议更新_Ver_1_3_0.xlsx`  
**转写日期:** 2026-08-19  

本文由硬件团队字节表原文件逐页转写，作为 App / 固件联调的字节级参考标准。
语义与裁决顺序以 `docs/Kirole_专注状态重连_App对接说明_Ver_1_3_0.md` 为准；
仓库总规格见 `docs/BLE通信协议规格文档.md`。三份冲突时，**以本表 + 对接说明的固件原文为准**，再回写总规格。

约定：多字节整数一律 Big Endian；字符串为 `Length(1B) + UTF-8`；Type 按方向解释。

## 说明

**Kirole BLE 通信协议 —— 命令字节表**

**依据《Kirole BLE 通信协议规格文档 2.10.1》及《Kirole 设备离线运行协议改动方案》整理 · 2026-08-18 · 所有大小单位均为字节（Byte） · Ver:1.3.0 · 保留 Ver 1.2.0 专注重连并新增完整 Schedule v2**

### 一、BLE 配置与通用约定

| 项目 | 值 | 大小 | 单位/属性 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| Service UUID | 0000FFE0-0000-1000-8000-00805F9B34FB | - | - | 设备广播包必须携带，App 只扫描带该 UUID 的外设 | §2.1 |
| Write characteristic | 0000FFE1-0000-1000-8000-00805F9B34FB | - | Write | App → Device 命令通道 | §2.2 |
| Notify characteristic | 0000FFE2-0000-1000-8000-00805F9B34FB | - | Notify | Device → App 事件通道 | §2.2 |
| 多字节整数 | Big Endian | - | - | 多字节整数一律大端（BE） | §3.6 |
| 有符号整数 | 二进制补码 | - | - | int8 等按二进制补码解释 | §3.6 |
| 字符串编码 | Length(1B) + UTF-8(NB) | 1+N | UTF-8 | Length 为字节数；App 保证仅可打印 ASCII 0x20–0x7E | §3.5 |
| Type 字节按方向解释 | Write 用第 4 节命令表 / Notify 用第 5 节事件表 | - | - | 同一 Type 值双向含义不同（如 0x10=DayPack / EnterTaskIn） | §2.4 |

### 二、通用数据包格式（简单包）

| 方向 | Type | Length | Payload | 帧长 | 说明 |
| --- | --- | --- | --- | --- | --- |
| App → Device | 1 字节 | 2 字节（BE） | N 字节 | 3 + N | packet.count 必须等于 3 + Length；尾部多余字节视为格式错误（§3.1） |
| Device → App | 1 字节 | 1 字节 | N 字节 | 2 + N | 简单事件包必须等于 2 + Length（§3.1/§5.1） |

### 三、分包格式（大 Payload，11 字节头，双向通用）

| 偏移 | 字段 | 大小 | 说明 |
| --- | --- | --- | --- |
| 0 | Type | 1 | 命令类型标识符（同 §3.1） |
| 1..2 | MessageId | 2 | 消息标识符（BE），同一消息的所有分包共享 |
| 3..4 | Seq | 2 | 分包序号（BE，从 0 开始）；重发必须从 Seq=0 整条重发（v2.5.24 由 1B 扩为 2B） |
| 5..6 | Total | 2 | 分包总数（BE），上限 65535（v2.5.24 由 1B 扩为 2B） |
| 7..8 | PayloadLen | 2 | 本分包 payload 长度（BE） |
| 9..10 | CRC16 | 2 | 本分包 payload 的 CRC16-CCITT-FALSE（BE） |
| 11.. | Payload | N | 分包 payload 数据 |

CRC16-CCITT-FALSE：多项式 0x1021、初值 0xFFFF、XOR out 0x0000、Reflect in/out false。适用于 0x03 / 0x10 / 0x11 / 0x15 / 0x16 / 0x1B 等大 payload；接收端按 MessageId 分槽重组，App 不发送分包级 ACK。

### 四、安全握手（0x7F，secure 模式连接后必须先握手）

| 消息 | Kind | 结构 | 总长 | 说明 |
| --- | --- | --- | --- | --- |
| ClientHello | 0x01 | kind(1) + clientNonce(8) + timestamp(4) + hmac(32) | 45 | App → Device，HMAC-SHA256，时间窗口 ±120 秒 |
| ServerHello | 0x02 | kind(1) + clientNonce(8) + serverNonce(8) + timestamp(4) + hmac(32) | 53 | Device → App，HMAC-SHA256，时间窗口 ±120 秒 |

### 五、SecureEnvelope（0x7E，secure 模式业务封装，总长 48 + N 字节）

| 偏移 | 字段 | 大小 | 说明 |
| --- | --- | --- | --- |
| 0 | version | 1 | 固定 0x02 |
| 1 | payloadType | 1 | 内层业务命令类型 |
| 2..9 | nonce | 8 | 随机数，防重放 |
| 10..13 | issuedAt | 4 | 签发时间戳（±120 秒窗口） |
| 14..15 | payloadLen | 2 | 内层 payload 长度（BE） |
| 16.. | payload | N | 内层业务 payload |
| 16+N.. | signature | 32 | HMAC-SHA256(version..payload) |

接收端必须校验签名、时间窗口与 nonce 重放；payloadLen 之后必须正好是 payload(NB) + signature(32B)。来源文件：F:\work\project\ODM\Kirole\document\Kirole BLE 通信协议规格文档2.10.1.md

## 命令总览

**命令总览**

**App → Device 命令 23 个（含安全帧） · Device → App 事件 24 个 · Ver 1.2.0 专注重连扩展保留 · Ver 1.3.0 新增完整 Schedule v2**

### App → Device 命令（23 个）

| Type | 名称 | Payload 长度 | 传输方式 | 说明 | 章节 |
| --- | --- | --- | --- | --- | --- |
| 0x01 | PetStatus | 变长 | 简单包 | 宠物状态信息 | §4.2 |
| 0x02 | TaskList | 变长 | 简单包 | 今日任务列表（最多 10 个） | §4.3 |
| 0x03 | Schedule | 变长 | 简单包 / 分包（11B 头） | 完整 Schedule v2 日程快照；包含日期、标题、描述、分类、结束时间与辅助文案 | §4.4 |
| 0x04 | Weather | 变长 | 简单包 | 当前天气信息 | §4.5 |
| 0x05 | Time | 6 | 简单包 | 时间同步 | §4.6 |
| 0x10 | DayPack | 变长 | 分包（11B 头） | 完整每日数据包 | §4.7 |
| 0x11 | TaskInPage | 变长 | 分包（11B 头） | 任务详情页数据 | §4.8 |
| 0x12 | DeviceMode | 1 | 简单包 | 设备运行模式 | §4.9 |
| 0x13 | SmartReminder | 变长 | 简单包 | AI 智能提醒推送 | §4.10 |
| 0x14 | FocusStatus | 25+N（v2） | 简单包 | 带 FocusSessionId / FocusRevision 的权威专注状态 | §4.11 / 专注重连页 |
| 0x15 | CustomAvatarFrame | 变长 | 分包（11B 头） | 候选头像暂存帧（v4，KRI） | §4.12 |
| 0x16 | Screensaver | 变长 | 简单包 / 分包 | 屏保金句 / 明信片 | §4.15 |
| 0x17 | SceneUnlock | 1 | 简单包 | 场景解锁 / 切换 | §4.16 |
| 0x18 | OTAReboot | 0 | 简单包 | 触发固件升级重启（零 payload） | §4.17 |
| 0x19 | WiFiDebugMode | 1 | 简单包 | PC Wi-Fi 调试模式控制 | §4.18 |
| 0x1A | WiFiAvatarSession | 5 | 简单包 | SoftAP 头像快速传输会话 | §4.20 |
| 0x1B | TaskListSnapshotAck | 变长 | 分包（11B 头） | 业务确认 + 完整任务快照 | §4.21 |
| 0x1C | ShippingMode | 1 | 简单包 | 开启运输模式 | - |
| 0x20 | EventLogRequest | 4 | 简单包 | 请求指定时间戳之后的事件日志 | §4.13 |
| 0x22 | AvatarControl | 21 | 简单包 | 头像事务控制（固定 21B） | §4.19 |
| 0x7E | SecureData | 48+N（变长） | 简单包 / 分包 | 安全业务封装（48+N 字节） | §3.4 |
| 0x7F | SecurityHandshake | 45 / 53（固定） | 简单包 | 安全握手（45 / 53 字节） | §3.3 |
| 0x25 | OfflineSync | 1 / 5 / 9 / 14 / 33 | 简单包 | 离线数据事务、操作确认及专注状态裁决（双向） | OfflineSync页 |

### Device → App 事件（24 个）

| Type | 名称 | Payload 长度 | 传输方式 | 说明 | 章节 |
| --- | --- | --- | --- | --- | --- |
| 0x01 | EncoderRotateUp | 0（无 Payload） | 简单事件包 | 旋钮向上旋转（顺时针） | §5.2 |
| 0x02 | EncoderRotateDown | 0（无 Payload） | 简单事件包 | 旋钮向下旋转（逆时针） | §5.2 |
| 0x03 | EncoderShortPress | 0（无 Payload） | 简单事件包 | 旋钮短按（确认） | §5.2 |
| 0x04 | EncoderLongPress | 0（无 Payload） | 简单事件包 | 旋钮长按 | §5.2 |
| 0x05 | PowerShortPress | 0（无 Payload） | 简单事件包 | 电源按钮短按 | §5.2 |
| 0x06 | PowerLongPress | 0（无 Payload） | 简单事件包 | 电源按钮长按 | §5.2 |
| 0x10 | EnterTaskIn | 18+N（v2） | 简单事件包 | 进入专注；携带操作 ID、专注会话 ID 与开始时间 | §5.3 / 专注重连页 |
| 0x11 | CompleteTask | 22+N（v2） | 简单事件包 | 完成任务并结束指定专注会话 | §5.4 / 专注重连页 |
| 0x12 | SkipTask | 22+N（v2） | 简单事件包 | 跳过任务并结束指定专注会话 | §5.5 / 专注重连页 |
| 0x13 | SelectedTaskChanged | 变长 | 简单事件包 | 切换选中任务 | §5.6 |
| 0x14 | WheelSelect | 变长 | 简单事件包 | 旋钮按下选择确认 | §5.10 |
| 0x15 | ViewEventDetail | 变长 | 简单事件包 | 查看日历事件详情 | §5.11 |
| 0x16 | ReminderAcknowledged | 4 | 简单事件包 | 确认智能提醒 | §5.12 |
| 0x17 | ReminderDismissed | 4 | 简单事件包 | 提醒超时自动消失 | §5.13 |
| 0x18 | OTAResult | 1 | 简单事件包 | OTA 升级重启应答 | §5.17 |
| 0x19 | WiFiDebugResult | 2 | 简单事件包 | Wi-Fi 调试模式实时应答 | §5.18 |
| 0x1A | WiFiAvatarSessionResult | 变长 | 简单事件包 | SoftAP 会话实时应答 | §5.20 |
| 0x20 | RequestRefresh | 5 | 简单事件包 | 请求数据刷新（v2.9） | §5.7 |
| 0x21 | EventLogBatch | 变长 | 简单事件包 | 批量回传事件日志 | §5.15 |
| 0x22 | AvatarControlResult | 31 | 简单事件包 | 头像事务实时结果（31B） | §5.19 |
| 0x30 | DeviceWake | 29 | 简单事件包 | 设备上线通知（29B） | §5.8 |
| 0x31 | DeviceSleep | 0（无 Payload） | 简单事件包 | 设备进入睡眠 | §5.9 |
| 0x40 | LowBattery | 1 | 简单事件包 | 设备电量低通知 | §5.14 |
| 0x25 | OfflineSync | 7 / 20 / 37+N / 变长 | 简单事件包 | 同步状态、专注快照、处理结果与离线操作批量补报 | OfflineSync页 |

### 说明：Payload 长度列引用各详解页的公式；secure 模式下业务帧封装进 0x7E SecureEnvelope。

## App命令-简单

**App → Device 命令详解（一）**

**单位：字节（Byte）；1+N = 1 字节长度前缀 + N 字节内容；… 表示偏移随变长字段累积**

### §4.2  PetStatus（0x01）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：宠物状态信息；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Name | 1+N | 20 | 长度前缀字符串 | 显示名（UTF-8 / 可打印 ASCII） |
| N+1 | Mood | 1 | - | H / E / F / S / M | 心情首字母（ASCII），见「枚举与状态码」页；固件当前阶段可忽略该字节 |
| N+2 | CharacterId | 1+N | 10 | joy / silas / nova | 伴侣 IP，恒为最近一次内置选择 |
| ... | CustomActive | 1 | - | 0x00 / 0x01 | 0x01=自定义形象激活（除专注页显示已持久化的 0x15 图）；0x00=按 CharacterId 渲染内置；固件读完 CharacterId 后必须再读此字节 |
| Payload 总长（字节） |  | 变长 | 可变：Name(1+N) + Mood(1) + CharacterId(1+N) + CustomActive(1)，N 由实际字符串长度决定 |  |  |
| 完整帧长（字节） |  | 3 + Payload（变长） | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.3  TaskList（0x02）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：今日任务列表（最多 10 个任务）｜Legacy：不含 TaskId / OperationID，不能作为 v2.9 Overview 的数据源；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | TaskCount | 1 | - | 0–10 | 任务数量 |
| 1+ | Tasks[] | 变长 | - | 见「子结构与记录」页 | 任务条目数组；每条 =TaskIdLength(1) + TaskId(N1, N1<=36) +<br>TitleLength(1) + Title(N2≤30) + IsCompleted(1) |
| Payload 总长（字节） |  | 变长 | 可变：1 + Σ(1 + N1 + 1 + N2 + 1（N1≤36，N2≤30）)； N1为TaskId，N2为Title |  |  |
| 完整帧长（字节） |  | 3 + Payload（变长） | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.4  Schedule（0x03，v2 / Ver 1.3.0）

### 方向：App → Device（FFE1 Write）｜传输：简单包或现有 11B 头分包｜用途：完整日程快照（最多 8 个事件）｜旧版 EventCount + Title + StartTime 格式严格拒绝；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | 1 | 固定 0x02 | Schedule v2 子版本；缺失或不是 0x02 时拒绝整包 |
| 1 | Year + Month + Day + EventCount | 4 | 1 / 1 / 1 / 1 | Year=0–99；Month=1–12；Day=有效日期；EventCount=0–8 | Year 保存公历年份减 2000；日期是本次完整日程快照的归属日 |
| 5+ | Events[] | 变长 | Time/EndTime=0 或 5；Title≤40；Description≤120；SupportText≤120 | 见「子结构与记录」及「Schedule-1.3」 | 每条依次为 Time + Title + Description + Category + EndTime + SupportText；Description 必须非空，Category=0x00–0x06 |
| Payload 总长（字节） |  | 变长 | 5 + Σ(6 + T + N + D + E + S)；T/E 为时间字节数，N/D/S 为标题、描述、辅助文案字节数 |  |  |
| 完整帧长（字节） |  | 简单包：3 + Payload；分包：每片 11 + 本片 Payload | 完整 Schedule Payload 可直接用简单包发送，或按现有 11B 头分包；设备重组完成后统一校验并原子应用 |  |  |

### §4.5  Weather（0x04）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：当前天气信息｜v2.5.9 起含 HighTemp / LowTemp，固件必须读到 LowTemp；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Temperature | 1 | - | int8（℃） | 当前温度 |
| 1 | Condition | 1+N | 15 | sun.max.fill 等 | 天气状况字符串（SF Symbol 值），见「枚举与状态码」页 |
| ... | HighTemp | 1 | - | int8（℃） | 当日最高温（v2.5.9 追加） |
| ... | LowTemp | 1 | - | int8（℃） | 当日最低温（v2.5.9 追加） |
| Payload 总长（字节） |  | 变长 | 可变：Temperature(1) + Condition(1+N≤15) + HighTemp(1) + LowTemp(1)，约 10 字节 |  |  |
| 完整帧长（字节） |  | 3 + Payload（变长） | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.6  Time（0x05）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：时间同步；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Year | 1 | - | 年份-2000 | 例如 26 = 2026 |
| 1 | Month | 1 | - | 1–12 | 月份 |
| 2 | Day | 1 | - | 1–31 | 日期 |
| 3 | Hour | 1 | - | 0–23 | 小时 |
| 4 | Minute | 1 | - | 0–59 | 分钟 |
| 5 | Second | 1 | - | 0–59 | 秒 |
| Payload 总长（字节） |  | 6 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 9 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.9  DeviceMode（0x12）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：设置设备运行模式；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Mode | 1 | - | 0x00 / 0x01 | 0x00=Interactive，0x01=Focus；仅为设置快照，不得用于进入、退出或裁决专注状态 |
| Payload 总长（字节） |  | 1 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 4 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.10  SmartReminder（0x13）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：AI 智能提醒推送；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | ReminderText | 1+N | 60 | 长度前缀字符串 | 提醒消息文本 |
| N+1 | ReminderType | 1 | - | 0x00 / 0x01 | 0x00=gentle 普通提醒，0x01=urgent 紧急提醒（加粗边框） |
| N+2 | PetMoodByte | 1 | - | H / E / F / S / M | 显示用宠物心情；固件当前阶段应忽略（同 §4.2 Mood） |
| Payload 总长（字节） |  | 变长 | 可变：ReminderText(1+N≤60) + ReminderType(1) + PetMoodByte(1) |  |  |
| 完整帧长（字节） |  | 3 + Payload（变长） | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.13  EventLogRequest（0x20）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：请求增量事件日志；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Since | 4 | - | UInt32 BE | Unix Timestamp；设备回传 timestamp > Since 的事件（EventLogBatch 0x21） |
| Payload 总长（字节） |  | 4 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 7 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.16  SceneUnlock（0x17）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：场景解锁 / 切换（替代旧 0xAA 01 01）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | SceneId | 1 | - | 0x00 / 0x01 / 0x02 | 0x00=harbor，0x01=forest，0x02=nightCity |
| Payload 总长（字节） |  | 1 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 4 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.15  Screensaver（0x16）

### 方向：App → Device（FFE1 Write）｜传输：分包（11B 头）｜用途：屏保金句 / 明信片（替代旧 0xAA 01 02）｜Quote+Author 较长时按 §3.2 分包；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | ContentType | 1 | - | 0x00 / 0x01 | 0x00=normal 金句，0x01=postcard 明信片 |
| 1 | SceneByte | 1 | - | 0x00–0x02 | 场景：0x00=harbor，0x01=forest，0x02=nightCity |
| 2 | PostcardDay | 1 | - | 0–255 | 明信片天数，无则为 0 |
| 3 | Quote | 1+N | 180 | 长度前缀字符串 | UTF-8 金句 |
| ... | Author | 1+N | 40 | 长度前缀字符串 | UTF-8 作者 |
| Payload 总长（字节） |  | 变长 | 可变：ContentType(1) + SceneByte(1) + PostcardDay(1) + Quote(1+N≤180) + Author(1+N≤40) |  |  |
| 完整帧长（字节） |  | 简单包 / 分包（11B 头） | 分包：Type(1B) + MessageId(2B) + Seq(2B) + Total(2B) + PayloadLen(2B) + CRC16(2B) + Payload |  |  |

### §4.17  OTAReboot（0x18）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：触发固件升级重启｜零 payload；固件校验 update.bin 合法后回 OTAResult 并立即重启；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| — | （无字段） | 0 | - | Length = 0 | 升级包不经 BLE 传输，由设备 WiFi AP 网页接收 update.bin（≤3MB） |
| Payload 总长（字节） |  | 0 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 3 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.18  WiFiDebugMode（0x19）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：开启 / 关闭 / 查询 PC Wi-Fi 调试模式｜明文帧示例：19 00 01 00（关闭）/ 01（开启）/ 02（查询）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Command | 1 | - | 0x00 / 0x01 / 0x02 | 0x00=关闭，0x01=开启，0x02=查询当前实际状态（不改变状态） |
| Payload 总长（字节） |  | 1 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 4 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.20  WiFiAvatarSession（0x1A）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：SoftAP 头像快速传输会话控制｜明文帧示例：1A 00 05 01 <OperationID 4B>；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Command | 1 | - | 0x00 / 0x01 / 0x02 | 0x00=close 停止 SoftAP，0x01=open 启动并回报凭据+端点，0x02=query 只读查询 |
| 1 | OperationID | 4 | - | UInt32 BE | 绑定本次头像事务（同 0x15/0x22 的 OperationID），须非零 |
| Payload 总长（字节） |  | 5 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 8 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### ShippingMode（0x1C）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：开启 设备运输模式｜明文帧示例：1C 00 01 01（打开运输模式）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Command | 1 | - | 0x01 | 开启运输模式，无ACK，app以断连作为生效信号 |
| Payload 总长（字节） |  | 1 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 4 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

约定：大小以字节（Byte）为单位；「1+N」= 1 字节长度前缀 + N 字节内容；「…」表示偏移随前面的变长字段累积；多字节整数一律 Big Endian。来源：Kirole BLE 通信协议规格文档 2.10.1。

## App命令-复杂

**App → Device 命令详解（二）**

**单位：字节（Byte）；1+N = 1 字节长度前缀 + N 字节内容；… 表示偏移随变长字段累积**

### §4.7  DayPack（0x10）

### 方向：App → Device（FFE1 Write）｜传输：分包（11B 头）｜用途：设备「概览」帧的完整每日数据包｜v2.5.0 破坏性重写；全字段按序存在、无条件写入，空字符串 = 1 字节 0x00；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Year | 1 | - | 年份-2000 | 例如 26 = 2026 |
| 1 | Month | 1 | - | 1–12 | 月份 |
| 2 | Day | 1 | - | 1–31 | 日期 |
| 3 | DeviceMode | 1 | - | 0x00 / 0x01 | 0x00=Interactive，0x01=Focus；设置类快照，App 当前恒发 0x00，不得用于判定专注态 |
| 4 | FocusChallengeEnabled | 1 | - | 0x00 / 0x01 | 0x00=禁用，0x01=启用 |
| 5 | PetDialogue | 1+N | 120 | 长度前缀字符串 | 宠物气泡（阶段感知，早安/陪伴/结算同一句变脸） |
| ... | EventCount | 1 | - | 0–N | 今日事件数 |
| ... | Events[] | 变长 | - | 见「子结构与记录」页 | 事件列表；每条 6 字段（Time/Title/Description/Category/EndTime/SupportText） |
| ... | TaskCount | 1 | - | 0–5 | 置顶任务数量（4寸≤3 / 7.3寸≤5） |
| ... | TopTasks[] | 变长 | - | 见「子结构与记录」页 | 置顶任务；每条 4 字段（TaskId/Title/IsCompleted/Priority） |
| ... | SettlementData | 10 | - | 定长数值 | 进度/专注数值，固定 10B（见「子结构与记录」页） |
| ... | DaySummary | 1+N | 180 | 长度前缀字符串 | 一天总结（情绪向，只谈日程 + 一条建议）；空串=尚未生成 |
| ... | FirstUp | 1+N | 60 | 长度前缀字符串 | 「First up:」下一项内容，App 算好下发 |
| ... | SettlementReview | 1+N | 180 | 长度前缀字符串 | 每日总结页·概况点评（v2.6.0）；空串=尚未生成 |
| ... | SettlementQuote | 1+N | 120 | 长度前缀字符串 | 每日总结页·金句/明日鼓励（v2.6.0）；DayPack 当前最后一个字段 |
| Payload 总长（字节） |  | 变长 | 可变：前 5B 定长 + PetDialogue 起全为变长流（含 Events[]/TopTasks[]），固件必须顺序流式解析 |  |  |
| 完整帧长（字节） |  | 简单包 / 分包（11B 头） | 分包：Type(1B) + MessageId(2B) + Seq(2B) + Total(2B) + PayloadLen(2B) + CRC16(2B) + Payload |  |  |

### §4.8  TaskInPage（0x11）

### 方向：App → Device（FFE1 Write）｜传输：分包（11B 头）｜用途：任务详情页数据（页面 3）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | TaskId | 1+N | 36 | 长度前缀字符串 | 与 Overview 条目一致的硬件任务 ID |
| N+1 | TaskTitle | 1+N | 40 | 长度前缀字符串 | 任务标题 |
| ... | TaskDescription | 1+N | 100 | 长度前缀字符串 | 任务描述 |
| ... | Encouragement | 1+N | 80 | 长度前缀字符串 | v2.10.0 起改装「支持性文字」，恒按 Deep Work 规则生成；空串合法（不渲染该行） |
| ... | FocusChallengeActive | 1 | - | 0x00 / 0x01 | 0x00=未激活，0x01=已激活 |
| Payload 总长（字节） |  | 变长 | 可变：TaskId(1+N≤36) + TaskTitle(1+N≤40) + TaskDescription(1+N≤100) + Encouragement(1+N≤80) + FocusChallengeActive(1) |  |  |
| 完整帧长（字节） |  | 简单包 / 分包（11B 头） | 分包：Type(1B) + MessageId(2B) + Seq(2B) + Total(2B) + PayloadLen(2B) + CRC16(2B) + Payload |  |  |

### §4.11  FocusStatus（0x14，SubVersion 0x02）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：同步完成后的权威专注状态；同步裁决完成前不得覆盖设备离线状态；详见「专注重连-1.2」页

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | - | 固定 0x02 | 旧版 0x14 仅用于不支持 v2 的固件 |
| 1..4 | FocusRevision | 4 | - | UInt32 BE | 小于设备已应用版本时必须拒绝 |
| 5..12 | FocusSessionId | 8 | - | 8B 原始会话 ID | BootSessionId(4B)+StartOperationID(4B) |
| 13..19 | StatusBlock | 7 | - | State(1)+Phase(1)+Bottles(1)+ElapsedSeconds(4) | 阶段和瓶子按权威时长派生，不做双方累加 |
| 20.. | TaskTitle + SegmentSeconds | 1+N+4 | N≤40 | TaskTitleLength(1)+TaskTitle(N)+SegmentSeconds(4) | 秒级同步；当前未打断连续时长 |
| Payload 总长（字节） |  | 25+N | 固定头 20B + TaskTitle(1+N) + SegmentSeconds(4) |  |  |
| 完整帧长（字节） |  | 3 + Payload（变长） | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

### §4.12  CustomAvatarFrame（0x15）

### 方向：App → Device（FFE1 Write）｜传输：分包（11B 头）｜用途：候选头像暂存帧（v4，唯一可接受版本）｜重组后 payload 上限 29 + 2,240,012 = 2,240,041B；v2.7 起只暂存，不直接切换显示；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | - | 固定 0x04 | 0x01/0x02/0x03 已废弃，收到时丢弃整帧 |
| 1 | OperationID | 4 | - | UInt32 BE | App 生成的单操作身份 |
| 5 | AvatarID | 16 | - | 16 原始字节 | 自定义伴侣 UUID；擦除与提交均按此精确匹配 |
| 21 | FileLength | 4 | - | UInt32 BE | 必须严格等于 KRIFile 字节数 |
| 25 | FileCRC32 | 4 | - | CRC-32/IEEE BE | KRIFile 的校验值 |
| 29 | KRIFile | N | 2,240,012 | KRI v1 文件 | 12B 小端文件头 + 直通 alpha BGRA 像素；无压缩、无行 padding、无尾数据 |
| Payload 总长（字节） |  | 变长 | v4 头固定 29B；KRIFile 最大 2,240,012B |  |  |
| 完整帧长（字节） |  | 简单包 / 分包（11B 头） | 分包：Type(1B) + MessageId(2B) + Seq(2B) + Total(2B) + PayloadLen(2B) + CRC16(2B) + Payload |  |  |

### §4.21  TaskListSnapshotAck（0x1B）

### 方向：App → Device（FFE1 Write）｜传输：分包（11B 头）｜用途：完成/跳过/刷新请求的业务确认 + 完整 Overview 任务快照｜固定头 16B + Tasks[]；长 payload 按 §3.2 分包，固件须完整重组后再应用；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | - | 固定 0x01 | 其他版本整帧拒绝 |
| 1 | Action | 1 | - | 0x11 / 0x12 / 0x20 | 原请求动作：0x11 Complete，0x12 Skip，0x20 Refresh |
| 2 | OperationID | 4 | - | UInt32 BE | 原样回显动作 OperationID；对 0x20 回显 RequestID；必须非零 |
| 6 | Result | 1 | - | 见枚举页 | 本次业务处理结果（applied / alreadyApplied / taskNotFound / invalidRequest / supersededByApp / internalError） |
| 7 | StateEpoch | 4 | - | UInt32 BE | App 任务快照世代；重装或世代重建后改变 |
| 11 | Revision | 4 | - | UInt32 BE | 同一 StateEpoch 内严格递增，首个有效快照从 1 开始 |
| 15 | TaskCount | 1 | - | 0–5 | 完整 Overview 清单条数：4寸 0–3，7.3寸 0–5 |
| 16+ | Tasks[] | 变长 | - | 见「子结构与记录」页 | 完整替换快照；每条 = TaskIdLength(1)+TaskId(N1≤36)+TitleLength(1)+Title(N2≤30)+IsCompleted(1)+Priority(1) |
| Payload 总长（字节） |  | 变长 | 固定头 16B（SubVersion..TaskCount）+ Tasks[] 变长 |  |  |
| 完整帧长（字节） |  | 简单包 / 分包（11B 头） | 分包：Type(1B) + MessageId(2B) + Seq(2B) + Total(2B) + PayloadLen(2B) + CRC16(2B) + Payload |  |  |

### §4.19  AvatarControl（0x22）

### 方向：App → Device（FFE1 Write）｜传输：简单包｜用途：提交 / 擦除 / 查询 / 取消头像事务；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Command | 1 | - | 0x01–0x05 | 0x01=commit，0x02=eraseExact，0x03=eraseAll，0x04=query，0x05=abort（详见枚举页） |
| 1 | OperationID | 4 | - | UInt32 BE | 头像事务操作 ID |
| 5 | AvatarID | 16 | - | 16 原始字节 | commit/eraseExact 必填；eraseAll/query/abort 全 16B 为 0 |
| Payload 总长（字节） |  | 21 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 24 | 简单包：Type(1B) + Length(2B, BE) + Payload |  |  |

约定：大小以字节（Byte）为单位；「1+N」= 1 字节长度前缀 + N 字节内容；「…」表示偏移随前面的变长字段累积；多字节整数一律 Big Endian。来源：Kirole BLE 通信协议规格文档 2.10.1。

## 子结构与记录

**子结构字段表与日志记录格式**

**供 0x02 / 0x03 / 0x10 / 0x1B / 0x21 等命令引用 · 单位：字节（Byte）**

### §4.3  TaskList · Task 条目（0x02）（子结构）

### TaskList(0x02) 内部结构：每条任务条目（由 TaskCount 指定条数，随后顺序编码）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | TaskIdLength | 1 | - | 0–36 | TaskId 的 UTF-8 字节数 |
| 1 | TaskId | N1 | 36 | UTF-8 | 硬件任务 ID；App 对超长外部 ID 生成 h- + 32 位十六进制摘要 |
| 1+N1 | TitleLength | 1 | - | 0–30 | Title 的 UTF-8 字节数 |
| ... | Title | N2 | 30 | UTF-8 | 任务标题 |
| ... | IsCompleted | 1 | - | 0x00 / 0x01 | 0x00=未完成，0x01=已完成 |
| ... | Priority | 1 | - | 1–3 | 优先级 |
| Payload 总长（字节） |  | 变长 | 每条可变：1 + N1 + 1 + N2 + 2（N1≤36，N2≤30） |  |  |

### §4.4  Schedule v2 · Event 条目（0x03，Ver 1.3.0）（子结构）

### Schedule v2（0x03）内部结构：EventCount 之后顺序编码；每条事件固定按 Time、Title、Description、Category、EndTime、SupportText 排列

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0+ | Time + Title | (1+T) + (1+N) | Time 0/5；Title 1–40 | 长度前缀 UTF-8 字符串 | Time 为空表示全天事件，否则必须为 HH:mm；Title 必须非空 |
| 变长 | Description + Category | (1+D) + 1 | Description 1–120；Category 1 | Description 非空；Category=0x00–0x06 | 描述必须能独立说明日程内容，禁止只发送标题 |
| 变长 | EndTime + SupportText | (1+E) + (1+S) | EndTime 0/5；SupportText 0–120 | 长度前缀 UTF-8 字符串 | 定时事件 EndTime 必须晚于 Time；全天事件两者均空；SupportText 可空 |
| Event 总长（字节） |  | 变长 | 每条 = 6 + T + N + D + E + S；Schedule Payload = 5 + Σ(每条 Event) |  |  |

### §4.7  DayPack · Event 条目（0x10）（子结构）

### DayPack(0x10) 内部结构：每条事件条目（6 字段，EventCount 之后顺序编码）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Time | 1+N | 8 | 长度前缀字符串 | 起始时间 "HH:mm"；全天事件为空串（1 字节 0x00） |
| ... | Title | 1+N | 40 | 长度前缀字符串 | 事件标题 |
| ... | Description | 1+N | 120 | 长度前缀字符串 | 事件描述（设计稿事件卡正文） |
| ... | Category | 1 | - | 0x00–0x06 | 事件类别（v2.5.27，AI 打标）；0x00=未分类不画图标，详见枚举页 |
| ... | EndTime | 1+N | 8 | 长度前缀字符串 | 结束时间 "HH:mm"（v2.6.0）；全天事件空串，跨午夜按 "23:59" 封顶 |
| ... | SupportText | 1+N | 120 | 长度前缀字符串 | 支持性文字（v2.10.0，按 Category 规则生成）；空串=未生成 |
| Payload 总长（字节） |  | 变长 | 每条可变：Time + Title + Description + Category(1) + EndTime + SupportText |  |  |

### §4.7  DayPack · TopTask 条目（0x10）（子结构）

### DayPack(0x10) 内部结构：每条置顶任务条目（4 字段，TaskCount 之后顺序编码）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | TaskIdLength | 1 | - | 0–36 | TaskId 的 UTF-8 字节数 |
| 1 | TaskId | N1 | 36 | UTF-8 | 硬件任务 ID；App 对超长外部 ID 生成 h- + 32 位十六进制摘要 |
| 1+N1 | TitleLength | 1 | - | 0–30 | Title 的 UTF-8 字节数 |
| ... | Title | N2 | 30 | UTF-8 | 任务标题 |
| ... | IsCompleted | 1 | - | 0x00 / 0x01 | 0x00=未完成，0x01=已完成 |
| ... | Priority | 1 | - | 1–3 | 优先级 |
| Payload 总长（字节） |  | 变长 | 每条可变：1 + N1 + 1 + N2 + 2（N1≤36，N2≤30） |  |  |

### §4.7  DayPack · SettlementData（定长 10B）

### DayPack(0x10) 内部结构：定长 10 字节数值块

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | TasksCompleted | 1 | - | clamp 0–255 | 已完成项数 = 已完成任务 + 已结束日程 |
| 1 | TasksTotal | 1 | - | clamp 0–255 | 总项数 = 当日全部任务 + 全部今日日程 |
| 2 | PointsEarned | 2 | - | UInt16 BE | 积分 |
| 4 | TotalFocusMinutes | 2 | - | UInt16 BE | 总专注时间（分钟） |
| 6 | FocusSessionCount | 1 | - | clamp 0–255 | 专注会话次数 |
| 7 | LongestFocusMinutes | 2 | - | UInt16 BE | 最长单次专注时间（分钟） |
| 9 | InterruptionCount | 1 | - | clamp 0–255 | 专注期间手机解锁次数 |
| 总长（字节） |  | 10 | 固定长度（字段均为定长字节） |  |  |

### §4.21  TaskListSnapshotAck · Task 条目（0x1B）（子结构）

### TaskListSnapshotAck(0x1B) 内部结构：每条任务条目（由 TaskCount 指定条数，随后顺序编码）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | TaskIdLength | 1 | - | 0–36 | TaskId 的 UTF-8 字节数 |
| 1 | TaskId | N1 | 36 | UTF-8 | 硬件任务 ID；App 对超长外部 ID 生成 h- + 32 位十六进制摘要 |
| 1+N1 | TitleLength | 1 | - | 0–30 | Title 的 UTF-8 字节数 |
| ... | Title | N2 | 30 | UTF-8 | 任务标题 |
| ... | IsCompleted | 1 | - | 0x00 / 0x01 | 当前正常发送恒为 0x00（快照只含未完成任务）；字节保留为结构与 TopTask 一致 |
| ... | Priority | 1 | - | 1–3 | 优先级 |
| Payload 总长（字节） |  | 变长 | 每条可变：1 + N1 + 1 + N2 + 2（N1≤36，N2≤30） |  |  |

### §5.15  EventLogBatch（0x21）· Record 记录格式（子结构）

### EventLogBatch(0x21) 内部结构：Count(1B) + Records[] 记录流

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Count | 1 | - | 0–255 | 本批次记录条数；App 严格校验整批长度，必须恰好解析出 Count 条 |
| 1+ | Records[] | 变长 | - | 见下表 | 顺序拼接的记录流；记录类型 1B + payload N B |
| Payload 总长（字节） |  | 变长 | 可变：1 + Σ(1 + 各记录 payload) |  |  |

### EventLogBatch · 各类事件记录字节长度（按事件类型）

事件类型 Payload 组成 记录总长

0x01–0x06、0x31 无 payload 1 字节

0x30（批量内） BatteryLevel(1B) 2 字节

0x18 StatusCode(1B) 2 字节

0x40 BatteryLevel(1B) 2 字节

0x16、0x17 Timestamp(4B) 5 字节

0x10 Length(1B) + TaskId(NB) + Timestamp(4B) 6+N 字节

0x11、0x12（v2.9） SubVersion(1B) + OperationID(4B) + TaskIdLength(1B) + TaskId(NB) + Timestamp(4B) 11+N 字节

0x13–0x15 Length(1B) + Id(NB) 2+N 字节

0x19、0x1A、0x20、0x22 禁止入批（实时应答/控制请求） —

约定：大小以字节（Byte）为单位；「1+N」= 1 字节长度前缀 + N 字节内容；「…」表示偏移随前面的变长字段累积；多字节整数一律 Big Endian。来源：Kirole BLE 通信协议规格文档 2.10.1。

## 设备事件-输入

**Device → App 事件详解（一）：输入与通知**

**单位：字节（Byte）；1+N = 1 字节长度前缀 + N 字节内容；简单事件包帧长 = 2 + Payload**

### §5.2  基础输入事件（0x01–0x06）（无 Payload）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：旋钮与电源输入｜无 payload：完整事件帧 = Type(1B) + Length(1B,=0) = 2 字节；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Type 0x01 EncoderRotateUp | 0 | - | 无 | Encoder 旋钮向上旋转（顺时针） |
| 0 | Type 0x02 EncoderRotateDown | 0 | - | 无 | Encoder 旋钮向下旋转（逆时针） |
| 0 | Type 0x03 EncoderShortPress | 0 | - | 无 | Encoder 旋钮短按（确认） |
| 0 | Type 0x04 EncoderLongPress | 0 | - | 无 | Encoder 旋钮长按 |
| 0 | Type 0x05 PowerShortPress | 0 | - | 无 | 电源按钮短按 |
| 0 | Type 0x06 PowerLongPress | 0 | - | 无 | 电源按钮长按 |
| Payload 总长（字节） |  | 0 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 2 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.3  EnterTaskIn（0x10，SubVersion 0x02）

### 方向：Device → App（FFE2 Notify）｜用途：专注开始；断连时立即本地生效并进入 OP_BATCH 等待队列，不等待 App 确认；详见「专注重连-1.2」页

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0..12 | SessionHeader | 13 | - | SubVersion(1)+OperationID(4)+FocusSessionId(8) | OperationID 非零；FocusSessionId 唯一 |
| 13.. | TaskId | 1+N | N≤36 | TaskIdLength(1)+TaskId(N) | 当前 Overview 条目的硬件任务 ID |
| 14+N..17+N | StartTimestamp | 4 | - | UInt32 BE Unix Timestamp | RTC 无效时置 0，由 App 按 elapsed 回推 |
| Payload 总长（字节） |  | 18+N | SubVersion(1)+OperationID(4)+FocusSessionId(8)+TaskId(1+N)+StartTimestamp(4) |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.6  SelectedTaskChanged（0x13）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：用户在概览页切换选中的任务；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Length | 1 | - | 0–255 | TaskId 长度 |
| 1 | TaskId | N | - | UTF-8 | 当前 Overview 条目的硬件任务 ID |
| Payload 总长（字节） |  | 变长 | 可变：Length(1) + TaskId(N) = 1+N |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.10  WheelSelect（0x14）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：Encoder 旋钮按下（旋钮选择确认）｜App 当前仅记录/调试，不回发页面数据；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Length | 1 | - | 0–255 | 选中项 ID 长度 |
| 1 | ItemId | N | - | UTF-8 | 选中项 ID |
| Payload 总长（字节） |  | 变长 | 可变：Length(1) + ItemId(N) = 1+N |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.11  ViewEventDetail（0x15）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：用户查看日历事件详情｜App 无需响应（自动超时返回概览页）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Length | 1 | - | 0–255 | EventId 长度 |
| 1 | EventId | N | - | UTF-8 | Event ID |
| Payload 总长（字节） |  | 变长 | 可变：Length(1) + EventId(N) = 1+N |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.12  ReminderAcknowledged（0x16）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：用户确认智能提醒；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Timestamp | 4 | - | UInt32 BE | Unix Timestamp |
| Payload 总长（字节） |  | 4 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 6 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.13  ReminderDismissed（0x17）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：智能提醒超时自动消失；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Timestamp | 4 | - | UInt32 BE | Unix Timestamp |
| Payload 总长（字节） |  | 4 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 6 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.7  RequestRefresh（0x20）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：设备请求数据刷新（v2.9 严格 v1）｜实时控制请求，禁止写入/重放到 EventLogBatch；专注期间固件约每 5 分钟周期发送；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | - | 固定 0x01 | 其他版本或空 payload 旧格式拒绝 |
| 1 | RequestID | 4 | - | UInt32 BE | 必须非零；对应 0x1B.OperationID；重试时原样复用 |
| Payload 总长（字节） |  | 5 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 7 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.8  DeviceWake（0x30）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：设备上线通知 / Wake Notify｜BLE Notify 建立后固件主动上报；v2.7 实时帧固定 29B（App 仍可读旧 0/1/4/9B 包）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | BatteryLevel | 1 | - | clamp 0–100 | 当前电量百分比 |
| 1 | FwMajor | 1 | - | 0–255 | 固件版本 Major（v2.5.19 追加） |
| 2 | FwMinor | 1 | - | 0–255 | 固件版本 Minor |
| 3 | FwPatch | 1 | - | 0–255 | 固件版本 Patch |
| 4 | AvatarState | 1 | - | 0x00 / 0x01 | 0x00=正式库存无头像，0x01=有 committed KRI |
| 5 | AvatarID | 16 | - | 16 原始字节 | 正式头像 UUID；AvatarState=0 时全填 0 |
| 21 | FileLength | 4 | - | UInt32 BE | committed KRI 文件长度；无图填 0 |
| 25 | AvatarCRC32 | 4 | - | CRC-32/IEEE BE | committed KRI 文件校验值；无图填 0 |
| Payload 总长（字节） |  | 29 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 31 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.9  DeviceSleep（0x31）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：设备进入睡眠模式｜无 payload；App 收到后回发一帧 0x16 Screensaver（v2.6.0 修正）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| — | （无字段） | 0 | - | Length = 0 | 完整事件帧 = Type(1B) + Length(1B) = 2 字节 |
| Payload 总长（字节） |  | 0 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 2 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.14  LowBattery（0x40）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：设备电量低通知；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | BatteryLevel | 1 | - | clamp 0–100 | 电量百分比；App 更新显示并推送低电量本地通知 |
| Payload 总长（字节） |  | 1 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 3 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

约定：大小以字节（Byte）为单位；「1+N」= 1 字节长度前缀 + N 字节内容；「…」表示偏移随前面的变长字段累积；多字节整数一律 Big Endian。来源：Kirole BLE 通信协议规格文档 2.10.1。

## 设备事件-动作与应答

**Device → App 事件详解（二）：任务动作与应答**

**单位：字节（Byte）；1+N = 1 字节长度前缀 + N 字节内容；简单事件包帧长 = 2 + Payload**

### §5.4  CompleteTask（0x11，SubVersion 0x02）

### 方向：Device → App（FFE2 Notify）｜用途：完成任务并结束专注会话；断连时设备立即退出并排队，不等待 ACK；详见「专注重连-1.2」页

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0..12 | SessionHeader | 13 | - | SubVersion(1)+OperationID(4)+FocusSessionId(8) | OperationID 非零；事件类型隐含结束原因 |
| 13 | TaskIdLength | 1 | - | 0–36 | TaskId UTF-8 字节数 |
| 14 | TaskId | N | 36 | UTF-8 | 与专注会话绑定的任务 ID |
| 14+N..17+N | EndTimestamp | 4 | - | UInt32 BE | 本地按键实际结束时间 |
| 18+N..21+N | ElapsedSeconds | 4 | - | UInt32 BE | 本会话设备累计秒数，用于重连校准 |
| Payload 总长（字节） |  | 22+N | SubVersion(1)+OperationID(4)+FocusSessionId(8)+TaskId(1+N)+EndTimestamp(4)+ElapsedSeconds(4) |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.5  SkipTask（0x12，SubVersion 0x02）

### 方向：Device → App（FFE2 Notify）｜用途：跳过任务并结束专注会话；断连时设备立即退出并排队，不等待 ACK；详见「专注重连-1.2」页

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0..12 | SessionHeader | 13 | - | SubVersion(1)+OperationID(4)+FocusSessionId(8) | OperationID 非零；事件类型隐含结束原因 |
| 13 | TaskIdLength | 1 | - | 0–36 | TaskId UTF-8 字节数 |
| 14 | TaskId | N | 36 | UTF-8 | 与专注会话绑定的任务 ID |
| 14+N..17+N | EndTimestamp | 4 | - | UInt32 BE | 本地按键实际结束时间 |
| 18+N..21+N | ElapsedSeconds | 4 | - | UInt32 BE | 本会话设备累计秒数，用于重连校准 |
| Payload 总长（字节） |  | 22+N | SubVersion(1)+OperationID(4)+FocusSessionId(8)+TaskId(1+N)+EndTimestamp(4)+ElapsedSeconds(4) |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.17  OTAResult（0x18）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：OTAReboot(0x18) 的应答事件｜方向双义；secure 模式必须经 0x7E 封装；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | StatusCode | 1 | - | 见枚举页 | 0x00=OK_START_UPGRADE；0x01–0x04、0xFF 为各类错误（详见「枚举与状态码」页） |
| Payload 总长（字节） |  | 1 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 3 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.18  WiFiDebugResult（0x19）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：WiFiDebugMode(0x19) 的实时应答｜固定 2 字节；明文帧示例：19 02 01 00（开启成功）；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Enabled | 1 | - | 0x00 / 0x01 | 当前实际状态（不是请求目标值）；其他值非法 |
| 1 | StatusCode | 1 | - | 见枚举页 | 0x00=OK，0x01–0x04、0xFF 为错误（详见枚举页） |
| Payload 总长（字节） |  | 2 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 4 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.20  WiFiAvatarSessionResult（0x1A）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：WiFiAvatarSession(0x1A) 的实时应答｜open 成功时携带一次性热点凭据 + HTTP 收图端点；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Command | 1 | - | 0x00 / 0x01 / 0x02 | 原样回显 open/close/query |
| 1 | OperationID | 4 | - | UInt32 BE | 原样回显请求中的 OperationID |
| 5 | Status | 1 | - | 见枚举页 | 本次命令处理结果（同 WiFiDebugResult 状态码） |
| 6 | SSID | 1+N1 | 32 | UTF-8 | SoftAP 名称；非 open 成功时 N1=0 |
| ... | Passphrase | 1+N2 | 63 | UTF-8 | SoftAP 密码（WPA2）；0 表示开放网络；非 open 成功时 N2=0 |
| ... | Gateway | 4 | - | IPv4 大端 | SoftAP 网关，通常 C0 A8 04 01 = 192.168.4.1；非 open 成功时填 0 |
| ... | Port | 2 | - | UInt16 BE | HTTP 收图端点端口（如 80/8080）；非 open 成功时填 0 |
| ... | Path | 1+N3 | 32 | UTF-8 | HTTP 收图端点路径（如 /avatar）；非 open 成功时 N3=0 |
| ... | Token | 1+N4 | 64 | UTF-8 | 会话一次性 Bearer token（绑 OperationID）；非 open 成功时 N4=0 |
| ... | TTL | 2 | - | UInt16 BE | SoftAP 等待上传存活秒数（如 120）；到期自动关闭会话 |
| Payload 总长（字节） |  | 变长 | 变长：Command(1)+OperationID(4)+Status(1)+SSID(1+N1)+Passphrase(1+N2)+Gateway(4)+Port(2)+Path(1+N3)+Token(1+N4)+TTL(2) |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.15  EventLogBatch（0x21）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：批量回传事件日志（响应 0x20）｜记录格式见「子结构与记录」页；整批必须恰好解析出 Count 条；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | Count | 1 | - | 0–255 | 本批次记录条数 |
| 1+ | Records[] | 变长 | - | 见子结构页 | eventType(1B) + eventPayload(NB) 顺序拼接 |
| Payload 总长（字节） |  | 变长 | 可变：Count(1) + Σ(1 + 各记录 payload) |  |  |
| 完整帧长（字节） |  | 2 + Payload（变长） | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

### §5.19  AvatarControlResult（0x22）

### 方向：Device → App（FFE2 Notify）｜传输：简单包｜用途：头像事务实时结果（固定 31B）｜只走当前 Notify，不写入 EventLogBatch；明文（secure 模式经 0x7E 封装）

| 偏移(字节) | 字段 | 大小(字节) | 上限(字节) | 取值/枚举 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | OperationID | 4 | - | UInt32 BE | staged 取自 0x15；命令结果原样回显该命令 OperationID |
| 4 | Status | 1 | - | 0x01–0x05 | 0x01=staged，0x02=committed，0x03=erased，0x04=state，0x05=aborted |
| 5 | AvatarState | 1 | - | 0x00–0x02 | 0x00=empty，0x01=staged，0x02=committed |
| 6 | CustomActive | 1 | - | 0x00 / 0x01 | 固件当前真实激活状态 |
| 7 | AvatarID | 16 | - | 16 原始字节 | empty 时全 16B 为 0；否则为当前 AvatarState 所指文件的 UUID |
| 23 | FileLength | 4 | - | UInt32 BE | 对应 staged 或 committed KRI 文件长度；empty 时为 0 |
| 27 | FileCRC32 | 4 | - | CRC-32/IEEE BE | 对应文件校验值；empty 时为 0 |
| Payload 总长（字节） |  | 31 | 固定长度（字段均为定长字节） |  |  |
| 完整帧长（字节） |  | 33 | 简单事件包：Type(1B) + Length(1B) + Payload |  |  |

约定：大小以字节（Byte）为单位；「1+N」= 1 字节长度前缀 + N 字节内容；「…」表示偏移随前面的变长字段累积；多字节整数一律 Big Endian。来源：Kirole BLE 通信协议规格文档 2.10.1。

## 枚举与状态码

**取值表：枚举与状态码**

**供各命令字段引用 · 单位：字节（Byte）**

### Mood（0x01 PetStatus / 0x13 PetMoodByte）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| H | Happy | 心情首字母（ASCII） |
| E | Excited |  |
| F | Focused |  |
| S | Sleepy |  |
| M | Missing You |  |

### CharacterId（0x01 PetStatus）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| joy | Joy（喜乐） | 伴侣 IP，内置形象 |
| silas | Silas（仁爱） |  |
| nova | Nova（节制 / 自律） |  |

### Condition（0x04 Weather 天气状况）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| sun.max.fill | 晴天 |  |
| cloud.fill | 多云 |  |
| cloud.sun.fill | 局部多云 |  |
| cloud.rain.fill | 雨天 |  |
| cloud.snow.fill | 雪天 |  |
| cloud.bolt.fill | 暴风雨 |  |

### Category（0x10 DayPack Event 类别，v2.5.27）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | 未分类（保留值） | 不画图标；App 自 v2.5.28 起不再发送，归类不了的一律按 0x03 下发 |
| 0x01 | Deep Work（深度工作/核心生产力） | 内置图标：沙漏 |
| 0x02 | Meetings & Synced（会议与协同沟通） | 内置图标：对话气泡 |
| 0x03 | Administrative & Routine（行政日常琐碎） | 内置图标：点赞 |
| 0x04 | Critical Deadlines（硬性死线与交付） | 内置图标：对勾 |
| 0x05 | Bio-Habits & Wellness（生物钟习惯与健康） | 内置图标：爱心 |
| 0x06 | Rest & Recharge（充能与私人生活） | 内置图标：笑脸 |

### DeviceMode / Phase（0x12 / 0x14）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | Interactive（0x12） / idle（0x14） | 0x12：交互模式；0x14：无活跃专注会话 |
| 0x01 | Focus（0x12） / warmup（0x14） | 0x14：当前未打断段 0–5 分钟 |
| 0x02 | building（0x14） | 当前未打断段 6–15 分钟 |
| 0x03 | deep（0x14） | 当前未打断段 16 分钟以上 |

### ReminderType（0x13 SmartReminder）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | Gentle | 普通提醒，标准显示 |
| 0x01 | Urgent | 紧急提醒，加粗边框显示 |

### SceneId / SceneByte（0x17 SceneUnlock / 0x16 Screensaver）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | harbor | 港口场景 |
| 0x01 | forest | 森林场景 |
| 0x02 | nightCity | 城市夜景场景 |

### ContentType（0x16 Screensaver）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | normal | 金句 |
| 0x01 | postcard | 明信片 |

### Command（0x19 WiFiDebugMode / 0x1A WiFiAvatarSession）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | close | 关闭 / 停止 SoftAP |
| 0x01 | open | 开启并回报状态（0x1A 附带凭据与端点） |
| 0x02 | query | 查询当前实际状态，不改变状态 |

### Command（0x22 AvatarControl）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x01 | commit | 原子提交已 staged 的同 OperationID+AvatarID 候选图并启用 |
| 0x02 | eraseExact | 仅在正式库存 AvatarID 精确相等时擦除并重建分区 |
| 0x03 | eraseAll | AvatarID 全 16B 为 0；退出登录/账户清理 |
| 0x04 | query | AvatarID 全 16B 为 0；查询 staged 或 committed 真实库存（只读） |
| 0x05 | abort | AvatarID 全 16B 为 0；仅 commit 前放弃候选临时文件 |

### Action（0x1B TaskListSnapshotAck）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x11 | Complete | 原请求动作为完成 |
| 0x12 | Skip | 原请求动作为跳过 |
| 0x20 | Refresh | 原请求动作为刷新（OperationID=RequestID） |

### Result（0x1B TaskListSnapshotAck）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | applied | 新操作已成功应用 |
| 0x01 | alreadyApplied | 首次收到该 OperationID 时任务已是完成状态 |
| 0x02 | taskNotFound | App 找不到 TaskId，任务状态未改变 |
| 0x03 | invalidRequest | 业务校验失败，或同一 OperationID 被复用于不同 payload |
| 0x04 | supersededByApp | App 已有更新的决定，本次设备动作未覆盖 |
| 0xFF | internalError | App 内部处理失败；设备保留上个已确认快照并可重试 |

### StatusCode（0x18 OTAResult）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | OK_START_UPGRADE | 升级包检查通过，发应答后立即重启进入升级（BLE 关闭约 20 秒） |
| 0x01 | ERR_NO_FILE | 无 update.bin；不重启 |
| 0x02 | ERR_FILE_SIZE | 文件大小异常（=0 或 >3MB）；不重启 |
| 0x03 | ERR_SD_CARD | SD 卡未挂载；不重启 |
| 0x04 | ERR_OTA_FAILED | 升级写入失败；不重启 |
| 0xFF | ERR_UNKNOWN | 未知错误；不重启 |

### StatusCode（0x19 WiFiDebugResult / 0x1A WiFiAvatarSessionResult Status）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | OK | 命令处理成功 |
| 0x01 | ERR_UNSUPPORTED | 当前固件/硬件不支持（App 回退 BLE 0x15） |
| 0x02 | ERR_BUSY | SoftAP 被 0x19 占用或另一会话进行中 |
| 0x03 | ERR_WIFI_INIT_FAILED | WiFi / SoftAP 初始化失败 |
| 0x04 | ERR_INVALID_COMMAND | 命令值或 payload 长度非法 |
| 0xFF | ERR_UNKNOWN | 未知错误 |

### Status / AvatarState（0x22 AvatarControlResult）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x01 / 0x01 | staged | 候选图已暂存（Status）；AvatarState=staged 表示指向 staged 候选 |
| 0x02 / 0x02 | committed | 已原子替换并启用（Status）；AvatarState=committed 表示正式库存 |
| 0x03 | erased（Status） | 擦除并重建分区成功 |
| 0x04 | state（Status） | query 返回当前状态 |
| 0x05 | aborted（Status） | 已取消事务 |
| 0x00 | empty（AvatarState） | 无头像文件 |

约定：以上取值均为字节值/字面值；来源：Kirole BLE 通信协议规格文档 2.10.1。

### FocusState（0x14 / 0x25，v1.2.0）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| 0x00 | idle | 无活动专注会话 |
| 0x01 | active | 会话正在计时 |
| 0x02 | endedPending | 本地已结束但结束操作尚未完成裁决 |

### StartSource / EndReason / FocusResolveResult（v1.2.0）

| 值 | 名称/说明 | 补充说明 |
| --- | --- | --- |
| StartSource 0x00 | appEstablished | 线上建立；重连继续沿用 App 原始开始时间 |
| StartSource 0x01 | deviceOffline | 断连期间设备按键建立；首次同步采用设备开始时间 |
| EndReason 0x00 | none | 活动会话，无结束原因 |
| EndReason 0x01 | complete | 设备短按完成 |
| EndReason 0x02 | skip | 设备长按跳过 |
| EndReason 0x03 | appEnd | App 已结束或撤挡板 |
| Resolve 0x00 | accepted | 设备状态已接受并成为权威状态 |
| Resolve 0x01 | closed | 结束优先；会话已关闭 |
| Resolve 0x02 | conflictResolved | 不同活动会话已按规则归并 |
| Resolve 0x03 | rejected | 载荷或会话关系非法；设备保留队列 |
| Resolve 0xFF | internalError | App 内部错误；设备保留并重试 |

## OfflineSync-0x25

**0x25 OfflineSync 双向协议详解 · Ver 1.3.0（保留 Ver 1.2.0 专注重连扩展）**

**方向：双向｜多字节整数：Big Endian｜OP_BATCH 保持原外层 Record；新增 FOCUS_RESOLVE(0x06) 与 FOCUS_STATE(0x83)**

### 一、命令与 Opcode 总览

| Type | Opcode | 名称 | 方向 | Payload 长度 | 作用 |
| --- | --- | --- | --- | --- | --- |
| 0x25 | 0x01 | BEGIN | App → 设备 | 14 | 开始离线数据同步事务 |
| 0x25 | 0x02 | COMMIT | App → 设备 | 5 | 原子启用已暂存的数据 |
| 0x25 | 0x03 | ABORT | App → 设备 | 5 | 放弃当前暂存数据 |
| 0x25 | 0x04 | QUERY | App → 设备 | 1 | 查询设备同步状态 |
| 0x25 | 0x05 | OP_ACK | App → 设备 | 9 | 确认离线操作已连续处理完成 |
| 0x25 | 0x80 | STATE | 设备 → App | 20 | 返回当前数据、事务和操作队列状态 |
| 0x25 | 0x81 | RESULT | 设备 → App | 7 | 返回同步处理结果 |
| 0x25 | 0x82 | OP_BATCH | 设备 → App | 6 + Records[] | 批量补报离线操作 |
| 0x25 | 0x06 | FOCUS_RESOLVE | App → 设备 | 33 | 确认专注操作处理完成并下发权威裁决 |
| 0x25 | 0x83 | FOCUS_STATE | 设备 → App | 37+N | 重连时上报当前专注快照；早于普通 FocusStatus |

### 二、BEGIN（Opcode 0x01）

### App → 设备｜简单包｜用于声明同步事务、版本、有效期和本次数据集范围

| 偏移(字节) | 字段 | 大小(字节) | 上限/取值 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x01 | BEGIN | 首字节 |
| 1..4 | SyncId | 4 | UInt32 BE，非零 | 本次同步事务 ID | COMMIT / ABORT / RESULT 必须对应 |
| 5..8 | Revision | 4 | UInt32 BE | 本次完整数据版本 | 提交后成为 ActiveRevision |
| 9..12 | ValidUntil | 4 | Unix Timestamp，UInt32 BE | 数据有效期截止时间 | 过期后停止触发新业务动作 |
| 13 | DatasetMask | 1 | bit0..bit2 | 本次包含的数据集合 | bit0(0x01)：TaskList \ bit1(0x02)：Schedule \ bit2(0x03)：DayPack<br>其他位必须为 0 |
| Payload 总长 | 14 | 完整帧长 | 17 | 传输 | 简单包：Type(1B)+Length(2B)+Payload |

### 三、COMMIT / ABORT（Opcode 0x02 / 0x03）

### App → 设备｜简单包｜COMMIT 原子切换数据；ABORT 放弃当前暂存数据

| 偏移(字节) | 字段 | 大小(字节) | 上限/取值 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 0x02 / 0x03 | COMMIT / ABORT | 首字节 |
| 1..4 | SyncId | 4 | UInt32 BE | 目标同步事务 ID | 不匹配时不得提交 |
| Payload 总长 | 5 | 完整帧长 | 8 | 传输 | 简单包：Type(1B)+Length(2B)+Payload |

### 四、QUERY（Opcode 0x04）

### App → 设备｜简单包｜查询当前离线数据、事务与待补报操作状态

| 偏移(字节) | 字段 | 大小(字节) | 上限/取值 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x04 | QUERY | 无其他字段 |
| Payload 总长 | 1 | 完整帧长 | 4 | 传输 | 简单包：Type(1B)+Length(2B)+Payload |

### 五、OP_ACK（Opcode 0x05）

### App → 设备｜简单包｜仅确认已连续成功处理到的最大 OperationID

| 偏移(字节) | 字段 | 大小(字节) | 上限/取值 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x05 | OP_ACK | 首字节 |
| 1..4 | BootSessionId | 4 | UInt32 BE | 设备启动会话 ID | 必须匹配 OP_BATCH |
| 5..8 | AckOperationID | 4 | UInt32 BE | 连续成功处理到的最大 OperationID | 设备据此删除已确认记录 |
| Payload 总长 | 9 | 完整帧长 | 12 | 传输 | 简单包：Type(1B)+Length(2B)+Payload |

### 六、STATE（Opcode 0x80）

### 设备 → App｜简单事件包｜返回当前有效数据、事务、待补报队列和启动会话

| 偏移(字节) | 字段 | 大小(字节) | 上限/取值 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x80 | STATE | 首字节 |
| 1..4 | ActiveRevision | 4 | UInt32 BE | 当前有效数据版本 | 无有效数据时按实现约定返回 0 |
| 5..8 | ValidUntil | 4 | Unix Timestamp，UInt32 BE | 当前数据有效期 | 到期需请求刷新 |
| 9 | DatasetMask | 1 | bit0..bit2 | 当前有效数据集合 | 其他位必须为 0 |
| 10 | StateFlags | 1 | bit0..bit4 | 状态标志 | 其他位保留 |
| 11 | PendingCount | 1 | 0..255 | 待补报离线操作数量（含 FocusStart / Complete / Skip） | 建议队列上限 64 条 |
| 12..15 | BootSessionId | 4 | UInt32 BE | 本次设备启动会话 ID | 与 OperationID 共同构成幂等键 |
| 16..19 | CurrentSyncId | 4 | UInt32 BE | 当前事务 ID | 无事务时为 0 |
| Payload 总长 | 20 | 完整帧长 | 22 | 传输 | 简单事件包：Type(1B)+Length(1B)+Payload |

### 七、RESULT（Opcode 0x81）

### 设备 → App｜简单事件包｜返回目标命令或事务的同步处理结果

| 偏移(字节) | 字段 | 大小(字节) | 上限/取值 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x81 | RESULT | 首字节 |
| 1..4 | SyncId | 4 | UInt32 BE | 对应同步事务 ID | 与 BEGIN 一致 |
| 5 | TargetType | 1 | 0x02 / 0x03 / 0x10 / 0x25 | 处理目标类型 | 原命令或 OfflineSync |
| 6 | ResultCode | 1 | 见结果码表 | 同步处理结果 | 只有 COMMITTED 表示离线数据准备完成 |
| Payload 总长 | 7 | 完整帧长 | 9 | 传输 | 简单事件包：Type(1B)+Length(1B)+Payload |

### 八、OP_BATCH（Opcode 0x82）与 Record

### 设备 → App｜简单事件包｜按 OperationID 顺序批量补报断连期间产生的原事件

| 偏移(字节) | 字段 | 大小(字节) | 上限/取值 | 说明 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x82 | OP_BATCH | 首字节 |
| 1..4 | BootSessionId | 4 | UInt32 BE | 设备启动会话 ID | 幂等键组成部分 |
| 5 | Count | 1 | 0..255 | 本批 Record 数量 | 接收端必须解析出 Count 条 |
| 6.. | Records[] | 变长 | Count 条 | 离线操作记录数组 | 按 OperationID 递增顺序 |
| Payload 总长 | 6 + Σ(6+N) | 完整帧长 | 2 + Payload | 传输 | 简单事件包；需满足 1B Length 上限 |

Record 偏移 字段 大小(字节) 上限/取值 说明 备注

0..3 OperationID 4 UInt32 BE，递增 离线操作 ID 同一 BootSessionId 内唯一

4 EventType 1 0x10 / 0x11 / 0x12 等原事件 Type；专注操作使用 v2 payload 原事件类型 字段定义保持不变

5 PayloadLen 1 0..255 OriginalPayload 字节数 必须与剩余字节一致

6.. OriginalPayload N 原事件 Payload 原事件载荷 专注操作字段定义见「专注重连-1.2」页

Record 总长 6 + N 幂等键 DeviceId + BootSessionId + OperationID ACK 规则 仅 ACK 连续处理成功的最大 OperationID

### 九、DatasetMask 位定义

| 位 | 掩码 | 数据集 | 对应命令 | 作用 | 约束 |
| --- | --- | --- | --- | --- | --- |
| bit0 | 0x01 | TaskList | 0x02 | 离线任务执行数据 | 以 0x02 为业务准则 |
| bit1 | 0x02 | Schedule | 0x03 | 完整独立 Schedule v2 日程快照 | 必须使用 Schedule v2；与 DayPack 同批提交时先应用 DayPack、再应用 Schedule，Schedule 对日程可见字段拥有最终优先级 |
| bit2 | 0x04 | DayPack | 0x10 | 当天展示与兜底数据 | 仅在掩码包含时下发 |
| bit3..bit7 | 保留 | - | - | 不得使用 | 必须为 0 |

### 十、StateFlags 位定义

| 位 | 掩码 | 名称 | 置 1 含义 | App 行为 | 备注 |
| --- | --- | --- | --- | --- | --- |
| bit0 | 0x01 | DataValid | 当前离线数据有效 | 可按 ValidUntil 使用 | 到期后不再触发新业务动作 |
| bit1 | 0x02 | TransactionOpen | 存在未完成事务 | 依据 CurrentSyncId 处理 | 断连或异常时可重新完整同步 |
| bit2 | 0x04 | NeedsFullSync | 需要完整同步 | 重新执行 BEGIN→数据集→COMMIT | 复位、掉电或 RAM 丢失后置位 |
| bit3 | 0x08 | OperationOverflow | 离线操作队列溢出 | 优先拉取并进行业务补偿 | 建议队列上限 64 条 |
| bit4 | 0x10 | FocusSyncPending | 存在未裁决专注快照或操作 | 先处理 FOCUS_STATE/OP_BATCH | 裁决完成前不得下发普通 0x14 覆盖设备 |
| bit5..bit7 | 保留 | - | 保留 | 忽略未知保留位 | 发送端不得主动置位 |

### 十一、ResultCode 建议值

| 值 | 名称 | 含义 | 适用阶段 | App 处理 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 0x00 | ACCEPTED | 已接受请求 | BEGIN / 命令 | 继续当前流程 |  |
| 0x01 | STAGED | 数据已暂存 | 0x02 / 0x03 / 0x10 | 等待全部数据后 COMMIT |  |
| 0x02 | COMMITTED | 事务已原子提交 | COMMIT | 标记离线数据准备完成 | 唯一成功完成标志 |
| 0x10 | INVALID_STATE | 当前状态不允许 | 任意 | 查询 STATE 后重试或全量同步 |  |
| 0x11 | MISSING_DATASET | 缺少 DatasetMask 指定数据 | COMMIT | 补齐数据或 ABORT 后重开事务 |  |
| 0x12 | EXPIRED | 数据有效期已过 | BEGIN / COMMIT | 使用新 ValidUntil 重建事务 |  |
| 0x13 | INVALID_PAYLOAD | Payload 非法 | 任意 | 修正编码后重发 |  |
| 0x14 | BUSY | 设备忙 | 任意 | 稍后重试 |  |
| 0xFF | INTERNAL_ERROR | 设备内部错误 | 任意 | 记录并重新查询状态 |  |

## 专注重连-1.2

**专注状态断连重连同步协议 · Ver 1.2.0**

**设备离线操作立即生效；重连先回放操作、再统一裁决、最后恢复普通 FocusStatus；本页全部为本次新增或修改内容**

### 一、同步原则

| 规则 | 触发 | 设备行为 | App 行为 | 时间规则 | 备注 |
| --- | --- | --- | --- | --- | --- |
| P1 | BLE 断连 | 仅本地有效按键可改变设备专注状态；立即生效 | 不得用旧缓存状态否定设备操作 | 记录秒级时间 | 在线行为保持现有流程 |
| P2 | 离线进入 | 生成 FocusSessionId，进入专注页并排队 FocusStart | 重连后接受设备会话并开启挡板 | 设备开始时间优先 | 不等待 TaskInPage/ACK |
| P3 | 线上进入后断连 | 保留原 FocusSessionId 并继续本地计时 | 保留原会话，不重复创建 | App 原开始时间优先 | 预计误差 ≤120 秒 |
| P4 | 离线退出 | 立即停止计时、退出页面并排队 Complete/Skip | 重连后撤挡板并只结算一次 | 结束优先 | 不等待 0x1B/超时 |
| P5 | 重连 | 先发 FOCUS_STATE 和 OP_BATCH | 先裁决再发普通 0x14 | Phase/Bottles 按权威时长派生 | 禁止双方数值相加 |

### 二、OfflineSync 专注 Opcode 总览

| Type | Opcode | 名称 | 方向 | Payload 长度 | 作用 |
| --- | --- | --- | --- | --- | --- |
| 0x25 | 0x06 | FOCUS_RESOLVE | App → Device | 33 | 确认离线操作处理完成并下发权威专注裁决 |
| 0x25 | 0x83 | FOCUS_STATE | Device → App | 37+N | 重连时主动上报当前专注快照；必须早于普通 0x14 |

### 三、FocusStatus（0x14，SubVersion 0x02）

### App → Device｜同步完成后的权威状态心跳；FocusRevision 旧于设备已应用版本时拒绝

| 偏移 | 字段 | 大小 | 取值 | 说明 | 约束 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | 固定 0x02 | FocusStatus v2 | 旧固件继续使用旧版结构 |
| 1..4 | FocusRevision | 4 | UInt32 BE | App 权威专注版本 | 状态变化严格递增 |
| 5..12 | FocusSessionId | 8 | 原始 8B | BootSessionId + StartOperationID | idle 时全 0 |
| 13 | FocusState | 1 | 0x00..0x02 | idle / active / endedPending | 见枚举页 |
| 14 | Phase | 1 | 0..3 | 显示阶段 | 按权威 elapsed 派生 |
| 15 | Bottles | 1 | 0..255 | 本会话能量瓶显示值 | 不得把双方瓶子相加 |
| 16..19 | ElapsedSeconds | 4 | UInt32 BE | 权威累计秒数 | 替代分钟级同步 |
| 20.. | TaskTitle | 1+N | N≤40 | 长度前缀任务标题 | idle 时 N=0 |
| 21+N..24+N | SegmentSeconds | 4 | UInt32 BE | 当前未打断连续秒数 | 会话结束时可为 0 |
| Payload 总长 | 25+N | 完整帧长 | 28+N | 传输 | 简单包：Type(1)+Length(2)+Payload |

### 四、EnterTaskIn（0x10，SubVersion 0x02）

### Device → App｜线上实时发送；断连时写入 OP_BATCH，设备立即进入专注

| 偏移 | 字段 | 大小 | 取值 | 说明 | 约束 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | 固定 0x02 | 专注操作 v2 | 其他版本拒绝 |
| 1..4 | OperationID | 4 | UInt32 BE 非零 | 本次开始操作 ID | 重传必须原样复用 |
| 5..12 | FocusSessionId | 8 | 原始 8B | BootSessionId + 本 StartOperationID | 全局幂等会话键 |
| 13.. | TaskId | 1+N | N≤36 | TaskIdLength + TaskId | 可打印 ASCII |
| 14+N..17+N | StartTimestamp | 4 | UInt32 BE | 开始 Unix 时间 | RTC 无效时置 0 |
| Payload 总长 | 18+N | 完整帧长 | 20+N | 传输 | 简单事件包；离线时作为 OP_BATCH.OriginalPayload |

### 五、CompleteTask / SkipTask（0x11 / 0x12，SubVersion 0x02）

### Device → App｜事件 Type 隐含 complete/skip；断连时本地立即退出并写入 OP_BATCH

| 偏移 | 字段 | 大小 | 取值 | 说明 | 约束 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | 固定 0x02 | 专注结束操作 v2 | 其他版本拒绝 |
| 1..4 | OperationID | 4 | UInt32 BE 非零 | 本次结束操作 ID | 重传必须原样复用 |
| 5..12 | FocusSessionId | 8 | 原始 8B | 要结束的会话 | 必须匹配活动会话 |
| 13.. | TaskId | 1+N | N≤36 | TaskIdLength + TaskId | 与开始操作一致 |
| 14+N..17+N | EndTimestamp | 4 | UInt32 BE | 本地按键结束时间 | RTC 无效时置 0 |
| 18+N..21+N | ElapsedSeconds | 4 | UInt32 BE | 设备累计秒数 | 用于回推与异常校验 |
| Payload 总长 | 22+N | 完整帧长 | 24+N | 传输 | 简单事件包；离线时作为 OP_BATCH.OriginalPayload |

### 六、FOCUS_RESOLVE（0x25 / Opcode 0x06）

### App → Device｜App 完成 OP_BATCH 幂等处理后下发；设备收到成功结果后才允许删除已 ACK 操作并接受普通 0x14

| 偏移 | 字段 | 大小 | 取值 | 说明 | 约束 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x06 | FOCUS_RESOLVE | 首字节 |
| 1..4 | ResolveID | 4 | UInt32 BE 非零 | 本次裁决请求 ID | 重试原样复用 |
| 5..12 | FocusSessionId | 8 | 原始 8B | 裁决后的活动/结束会话 | idle 且无历史目标时全 0 |
| 13 | FocusState | 1 | 0x00..0x02 | 最终状态 | 见枚举页 |
| 14 | ResolveResult | 1 | 见枚举页 | accepted/closed/conflictResolved 等 | 失败时设备保留队列 |
| 15..18 | StartTimestamp | 4 | UInt32 BE | 权威开始时间 | 离线创建采用设备时间 |
| 19..22 | EndTimestamp | 4 | UInt32 BE | 权威结束时间 | 活动会话为 0 |
| 23..26 | ElapsedSeconds | 4 | UInt32 BE | 权威累计秒数 | 用于设备立即校准 |
| 27..30 | FocusRevision | 4 | UInt32 BE | 裁决后的权威版本 | 后续 0x14 不得小于此值 |
| 31 | Phase | 1 | 0..3 | 裁决后显示阶段 | 按 elapsed 派生 |
| 32 | Bottles | 1 | 0..255 | 裁决后显示瓶子 | 不得累加双方值 |
| Payload 总长 | 33 | 完整帧长 | 36 | 传输 | 简单包：Type(1)+Length(2)+Payload |

### 七、FOCUS_STATE（0x25 / Opcode 0x83）

### Device → App｜Notify 就绪后顺序：DeviceWake → STATE → FOCUS_STATE → OP_BATCH；同步完成前 App 禁止用普通 0x14 覆盖设备

| 偏移 | 字段 | 大小 | 取值 | 说明 | 约束 |
| --- | --- | --- | --- | --- | --- |
| 0 | Opcode | 1 | 固定 0x83 | FOCUS_STATE | 首字节 |
| 1..4 | FocusRevision | 4 | UInt32 BE | 设备已应用版本 | 本地离线变化也递增 |
| 5..8 | BootSessionId | 4 | UInt32 BE | 设备启动会话 ID | 与 OperationID 组成幂等键 |
| 9..16 | FocusSessionId | 8 | 原始 8B | 当前或待裁决会话 | idle 且无待裁决会话时全 0 |
| 17 | FocusState | 1 | 0x00..0x02 | 本地当前状态 | 见枚举页 |
| 18 | StartSource | 1 | 0x00/0x01 | appEstablished/deviceOffline | 决定开始时间权威来源 |
| 19 | TaskIdLength | 1 | 0..36 | 任务 ID 字节数 | idle 可为 0 |
| 20..19+N | TaskId | N | ASCII | 会话任务 ID | 长度必须精确匹配 |
| 20+N..23+N | StartTimestamp | 4 | UInt32 BE | 设备记录的开始时间 | RTC 无效为 0 |
| 24+N..27+N | EndTimestamp | 4 | UInt32 BE | 设备记录的结束时间 | 活动会话为 0 |
| 28+N..31+N | ElapsedSeconds | 4 | UInt32 BE | 设备累计秒数 | 时间对齐依据 |
| 32+N..35+N | LastOperationID | 4 | UInt32 BE | 最近相关操作 ID | 用于诊断与完整性检查 |
| 36+N | EndReason | 1 | 0x00..0x03 | none/complete/skip/appEnd | 见枚举页 |
| Payload 总长 | 37+N | 完整帧长 | 39+N | 传输 | 简单事件包：Type(1)+Length(1)+Payload |

### 八、重连同步顺序

| 步骤 | 触发 | 设备发送/处理 | App 发送/处理 | 完成条件 | 禁止行为 |
| --- | --- | --- | --- | --- | --- |
| 1 | Notify Enabled | 发送 DeviceWake | 建立本次连接上下文 | DeviceWake 已接收 | 立即下发旧 0x14 |
| 2 | DeviceWake 后 | 发送 OfflineSync STATE | 检查 PendingCount/FocusSyncPending | STATE 已解析 | 跳过待补报检查 |
| 3 | 存在或曾存在会话 | 发送 FOCUS_STATE | 冻结普通 FocusStatus 下发 | 快照已接收 | 用 App idle 覆盖设备 active |
| 4 | PendingCount>0 | 按 OperationID 发送 OP_BATCH | 幂等、顺序处理完整批次 | 连续处理到最大 ID | 部分失败仍越级 ACK |
| 5 | 操作处理完成 | 等待确认，保持队列 | 发送 OP_ACK + FOCUS_RESOLVE | 裁决成功且版本匹配 | 先删队列后确认 |
| 6 | 裁决完成 | 应用权威状态并恢复心跳 | 发送 TaskInPage/FocusStatus/DayPack | 双方同一会话与 revision | 重复创建或重复结算 |

### 九、状态冲突裁决

| 设备状态 | App 状态 | 裁决结果 | 权威开始时间 | 权威结束时间 | 结算/页面行为 |
| --- | --- | --- | --- | --- | --- |
| 离线新进入且 active | idle | 接受设备会话 | 设备 start | 0 | App 立即开启挡板；设备保持当前页 |
| 离线 start 后已 end | idle | 生成一次历史会话 | 设备 start | 设备 end | 不闪开挡板；只结算一次 |
| 线上会话仍 active | 同一会话 active | 保持原会话 | App 原 start | 0 | 设备对齐 App；不重发 start |
| 设备已 end | 同一会话 active | 结束优先 | 原 start | 设备 end | App 撤挡板并结算 |
| 设备 active | 同一会话已 end | 结束优先 | 原 start | App end | 设备立即退出并停止计时 |
| 双方都 end | 同一会话已 end | 保持结束 | 原 start | 较早有效 end | 去重后仅结算一次 |
| active，会话 ID 不同 | 另一 active 会话 | 设备待同步 Start 优先，关闭旧 App 会话 | 设备 start | 旧会话截断到设备 start | 记录 conflictResolved 日志 |

### 十、时间、幂等与可靠性

| 主题 | 规则 | 正常阈值 | 异常处理 | 设备要求 | App 要求 |
| --- | --- | --- | --- | --- | --- |
| 计时精度 | 协议统一传秒，不使用分钟做重连裁决 | 差值 ≤120 秒 | 差值>120秒记录异常但不创建新会话 | 保留本地单调 elapsed | 按会话来源选择 start |
| 瓶子/阶段 | 按权威 elapsed 重新计算 | 同规则结果一致 | 不允许双方相加 | 裁决前可显示本地值 | 裁决后下发最终值 |
| 幂等键 | DeviceId+BootSessionId+OperationID | 全局唯一 | 重复 payload 不重复执行 | 重试复用原字节 | 账本去重 |
| 会话键 | FocusSessionId=BootSessionId+StartOperationID | 8B 固定 | 不允许复用 | 本地持久保存 | 所有起止/结算绑定会话 |
| ACK | 仅 ACK 连续成功处理的最大 OperationID | 累计 ACK | 缺口后停止 ACK | 仅删除已 ACK 记录 | 不可越过失败记录 |
| 持久化 | 未确认操作和当前专注状态跨重启保留 | 队列建议 64 | 溢出置 OperationOverflow+NeedsFullSync | 不得静默丢弃 | 执行完整状态核对 |

## Schedule-1.3

**Schedule v2（0x03）完整日程协议 · Ver 1.3.0**

**App → Device｜Big Endian｜简单包或现有 11 字节分包｜完整快照原子应用｜所有长度均按 UTF-8 字节数计算**

### 一、Payload 字段偏移

| 偏移 | 字段 | 大小 | 取值 / 上限 | App 发送要求 | 设备校验与说明 |
| --- | --- | --- | --- | --- | --- |
| 0 | SubVersion | 1 | 固定 0x02 | 必须显式发送 | 不是 0x02 或缺失时严格拒绝整包 |
| 1 | Year | 1 | 0–99 | 公历年份减 2000 | 与 Month、Day 组成有效日期 |
| 2 | Month | 1 | 1–12 | 发送日程归属月份 | 超范围拒绝 |
| 3 | Day | 1 | 有效日 | 发送日程归属日期 | 必须与 Year、Month 组成有效日期 |
| 4 | EventCount | 1 | 0–8 | 后续 Event 数量必须一致 | 数量或剩余字节不一致时拒绝整包 |
| 5+ | Events[] | 变长 | 见下表 | 连续编码 EventCount 条记录 | 完整解析成功后一次性应用，不部分更新 |

### 二、Event 字段顺序（固定为六字段）

| 顺序 | 字段 | 编码 | 长度 / 枚举 | 是否可空 | 规则 |
| --- | --- | --- | --- | --- | --- |
| 1 | Time | Length(1) + UTF-8(T) | T=0 或 5 | 全天事件可空 | 非空时必须为 HH:mm |
| 2 | Title | Length(1) + UTF-8(N) | 1≤N≤40 | 不可空 | 日程标题 |
| 3 | Description | Length(1) + UTF-8(D) | 1≤D≤120 | 不可空 | 必须提供可见日程描述，禁止只有标题 |
| 4 | Category | uint8 | 0x00–0x06 | 不可空 | 超出枚举范围拒绝整包 |
| 5 | EndTime | Length(1) + UTF-8(E) | E=0 或 5 | 全天事件可空 | 定时事件必须为 HH:mm 且晚于 Time；不支持跨午夜 |
| 6 | SupportText | Length(1) + UTF-8(S) | 0≤S≤120 | 可空 | 辅助文案；空字符串编码为 0x00 |

### 三、长度、时间与兼容规则

Schedule Payload 5 + Σ(6 + T + N + D + E + S)

简单包完整帧 Type(1) + Length(2, BE) + Payload，即 3 + Payload

定时事件 Time 与 EndTime 均为 5 字节 HH:mm，且结束时间晚于开始时间

全天事件 TimeLength=0 且 EndTimeLength=0；不得只将其中一个置空

跨午夜 当前版本不支持；App 必须拆成两个日期内事件或不发送

旧版简化 Schedule EventCount + Title + StartTime 格式严格拒绝，不做猜测或降级解析

字符编码 所有字符串均为 Length(1B) + UTF-8；Length 是字节数，不是字符数

### 四、Schedule 与 DayPack 比较及覆盖顺序

条件 / 顺序 比较对象 设备动作 日程显示 DayPack 其他字段 App 约束

可见字段完全相同 日期 + 每条 Time/Title/Description/Category/EndTime/SupportText，且顺序一致 不替换、不触发刷新 保持当前内容 保持不变 可不重复下发；若下发，结果仍应幂等

任一可见字段不同 字段值、事件数或事件顺序任一不同 完整 Schedule 原子替换日程与日期字段 显示 Schedule 的完整描述 PetDialogue、TopTasks、SettlementData、DaySummary、FirstUp 等保持不变 必须发送完整快照，不发送局部补丁

普通连接内顺序 DayPack 与 Schedule 均到达 先应用到达的 DayPack；Schedule 校验成功后按上述规则比较 Schedule 对日程字段最终优先 DayPack 非日程字段继续生效 不要用后到的旧 DayPack 覆盖已确认的 Schedule

OfflineSync 同批 DatasetMask 同时含 bit1 Schedule 与 bit2 DayPack 固定先应用 DayPack，再应用 Schedule Schedule 对日程可见字段最终优先 DayPack 非日程字段保持 批次提交前完成两者校验

### 五、App 发送与分包要求

完整性 每次发送完整日期快照；EventCount、字段长度与剩余字节必须精确一致

简单包 小 Payload 使用 Type(0x03) + Length(2B, BE) + 完整 Payload

11B 分包 大 Payload 可使用 Type + MessageId(2) + Seq(2) + Total(2) + PayloadLen(2) + CRC16(2) + 片段 Payload

分包重组 同一 MessageId；Seq 从 0 开始；重发从 Seq=0 整条重发；设备重组完成后再解析 Schedule v2

CRC 每片 Payload 使用 CRC16-CCITT-FALSE：poly 0x1021、init 0xFFFF、xorout 0x0000、reflect false

失败处理 任一字段、日期、枚举、时间、长度、CRC 或分包关系非法时拒绝整条消息，并保留现有日程

### 六、十六进制示例（均为简单包完整帧）

示例 内容

零事件 03 00 05 02 1A 08 12 00

零事件解码 Type=0x03；PayloadLength=5；SubVersion=0x02；日期=2026-08-18；EventCount=0

单事件 03 00 34 02 1A 08 12 01 05 30 39 3A 30 30 07 53 74 61 6E 64 75 70 0A 44 61 69 6C 79 20 73 79 6E 63 02 05 30 39 3A 33 30 0E 53 68 61 72 65 20 62 6C 6F 63 6B 65 72 73

单事件解码 09:00｜Standup｜Daily sync｜Category=0x02｜09:30｜Share blockers；PayloadLength=52(0x0034)

### 七、验收规则

1 零事件与单事件示例可按字段边界完整解析，且解析后无剩余字节

2 Description 为空、Title 为空、Category>0x06、非法日期/时间或定时事件 EndTime≤Time 时整包拒绝

3 旧版简化 Schedule 无 SubVersion=0x02，必须严格拒绝且不得改变当前显示

4 相同 Schedule 与 DayPack 不替换、不刷新；任一可见字段不同则显示完整 Schedule 描述

5 Schedule 替换日程后，DayPack 的 PetDialogue、TopTasks、SettlementData、DaySummary、FirstUp 等保持不变

6 简单包与 11B 分包重组后的业务结果一致；失败时保留原有日程

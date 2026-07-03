# Kirole BLE 通信协议规格文档

**版本:** v2.5.16
**更新日期:** 2026-07-03
**状态:** DayPack 显示模型重写（1 气泡 + 数据面板）。**破坏性变更：固件需按新 §4.7 / §6 重写 DayPack 解析（与 §8.7 修复一并做）。** FocusStatus(`0x14`) 新增 `SegmentMinutes` 字段（追加在 TaskTitle 后，前向兼容）；`ElapsedTime` 保持「本会话累计分钟」语义不变（v2.5.5）。`Mood`/`PetMoodByte` 明确为**前向兼容通道**：App 持续下发真实心情值，固件当前阶段可忽略、不据此展示或换图（v2.5.6，§4.2 / §4.10）。DayPack 末尾追加 `DaySummary`（框②「一天总结」：情绪向·只谈日程·≤180B），作为面板文本字段复活、与单句 `PetDialogue` 互补，不回退单气泡决策（v2.5.7，§4.7 / §6.5）。DayPack 再追加 `FirstUp`（框③「下一项」：下一个未来事件「HH:mm 标题」/ 无则置顶任务 / ≤60B，App 算好下发，现为 DayPack 最后一个字段）（v2.5.8，§4.7）。Weather(`0x04`) 在 Condition 后追加 `HighTemp`/`LowTemp`（顶栏高/低温，各 1B 有符号 int8）（v2.5.9，§4.5）。屏保金句/明信片（`Screensaver`）从旧 `0xAA 01 02` 开发命令升级为 `0x16` 业务帧（经 SecureEnvelope，**secure 模式可发**；旧开发命令在配置 `BLE_SHARED_SECRET` 后被禁用、屏保静默发不出去）（v2.5.10，§4.15）。场景解锁（`SceneUnlock`）同样从旧 `0xAA 01 01` 开发命令升级为 `0x17` 业务帧（secure 可发）；至此两条 `0xAA` 开发显示命令全部退役（v2.5.11，§4.16 / §4.14）。§4.15 澄清屏保帧传输：Quote/Author 较长或 secure 封装后整体可能超过协商 MTU 而**分包**（按 §3.2 通用分包重组），并非恒为单包；固件须按分包处理（v2.5.12）。新增 §6.6 字体与排版：两套字库（Lugrasimo=宠物气泡 / Calibri=其余所有文本）按**字段语义角色**渲染、字体不走 wire、App 不传字体字节、固件按字段映射 + 字形回退（v2.5.13，纯文档）。§3.5 补记 App 出站文本 **ASCII 净化保证**：所有字符串字段在编码边界被净化为仅含可打印 ASCII（`0x20`–`0x7E`），非 ASCII（LLM 弯引号/破折号/省略号、用户/日历带入的 emoji/重音/CJK 等）转写为 ASCII 近似或丢弃——固件收到的文本字段恒为 ASCII，§6.6 的 Lugrasimo 缺字回退随之从常态降级为兜底（v2.5.14，§3.5/§6.6）。同记 `RequestRefresh(0x20)` 联调期**去抖合并**：固件把 0x20 当 ~2s 心跳，App 用 60s 合并窗把整轮 sync 去抖为 ≤1 次/分（v2.5.14，§8.5）。两者均为 App 侧行为，wire 格式不变。面板态判定拍板：**不新增 `PanelMode` 字节**，态 A/B/C 由固件本地状态机判定（本地 RTC + 已收数据 + 按键），App 只负责内容与校时——与 Pebble Timeline / BLE CTS / InfiniTime 同类分工一致；新增 §6.7 判定规则，§6.5 开放问题关闭（v2.5.15，纯文档、wire 不变）。§8.5 补记 `Time(0x05)`→`RequestRefresh(0x20)` **反射回路与 DayPack 双发**（2026-07-03 联调：MsgID 连号、~3 秒差、除 PetDialogue 外相同的两个 DayPack）——App 侧已修（组包前等待在途对话生成，首轮即最终文本；反射补跑轮内容无变化时不再携带 DayPack）；**固件侧建议**：收到 Time 帧不应触发 0x20（0x20 仅用于开机后久无数据与用户物理按键），渲染进行中收到新 DayPack 应合并到下一次刷新。§4.7 补记 TopTasks **实现对齐**：规格上限一直是 4寸≤3 / 7.3寸≤5，App 端此前固定按 4 寸档发 ≤3 条，build 589 起按 Settings 配置的屏型发满上限、同优先级截取顺序确定化（priority→dueDate→id）。均为 App 行为 / 文档记录，wire 不变（v2.5.16，§8.5/§4.7）。

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
9. [专注时间计算](#9-专注时间计算)
10. [Spectra 6 像素数据格式](#10-spectra-6-像素数据格式)
11. [附录 A：Swift 类型参考](#附录-aswift-类型参考)

---

## 1. 协议概述

### 1.1 用途

本文档定义了 Kirole iOS App 与 E-ink 硬件设备之间的 BLE 通信协议。该协议支持：

- 从 App 向设备发送每日数据（Day Pack）
- 从设备向 App 接收用户交互事件
- 实时任务状态同步

### 1.2 阅读顺序

第一次硬件联调请先阅读 `BLE初次联调指南.md`。本文是完整协议参考，不代表第一轮联调要全部实现。

第一轮联调只验证 BLE 广播、连接、基础收发、简单包和 DayPack 分包接收。安全握手、离线批量日志、图片帧、智能提醒、专注状态、TaskInPage 细节页可以后续逐项加入。

### 1.3 修订历史

| 版本 | 日期 | 变更内容 |
|---------|------------|----------------------------------|
| v1.0.0  | 2026-01-30 | 初始协议规格 |
| v1.1.0  | 2026-01-31 | 新增 WheelSelect、ViewEventDetail、LowBattery 事件 |
| v1.2.0  | 2026-02-12 | 新增 Spectra 6 像素格式、Encoder/Power 按钮事件文档 |
| v1.3.0  | 2026-02-12 | Message House：新增 SmartReminder (0x13) 命令、扩展 DayPack/TaskInPage、SettlementData 专注指标、ReminderAcknowledged/Dismissed 事件 |
| v1.3.1  | 2026-02-12 | 新增 Section 3.2 九字节分包格式；Spectra 6 部分新增交叉引用至硬件需求文档 |
| v2.0.0  | 2026-02-21 | 新增安全握手与 SecureEnvelope（HMAC-SHA256）；MVP 默认兼容旧协议（未配置密钥时） |
| v2.1.0  | 2026-05-07 | 对齐当前 App 协议：PetStatus 增加 CharacterId；DayPack/TaskInPage 删除旧任务拆分字段；标注开发显示命令 |
| v2.2.0  | 2026-05-08 | 新增 FocusStatus (0x14) 命令（Release 构建实时推送专注状态与能量瓶子数）；BLEDataType enum 已移至 `Core/BLE/BLEProtocol.swift` 单一真相源 |
| v2.2.1  | 2026-05-08 | 新增 8.4 App 侧写入限流说明（20次/秒上限、RequestRefresh 2秒最小间隔）；新增 8.5 TOFU 设备信任模型说明 |
| v2.3.0  | 2026-05-08 | DeviceWake (0x30) payload 新增 BatteryLevel(1B)；App 侧在 DeviceWake 及 LowBattery 时更新并展示设备电量；旧固件兼容（空 payload 时保留 "—"） |
| v2.3.1  | 2026-05-08 | 修正：移除页面 4 内容描述中的"当前连续天数"（streak 系统已删除，SettlementData 字段表本就不含此字段）；~~Connection Timeout 改为 10s~~ 此项 v2.3.3 已撤回 |
| v2.3.2  | 2026-05-08 | 修正：WheelSelect(0x14) 按当前 App 代码仅记录/调试，不回发详情；TaskInPage 仍只由 EnterTaskIn(0x10) 触发 |
| v2.3.3  | 2026-05-08 | 撤回 v2.3.1 错误修订：Connection Timeout 仍为 15 秒（`BLEService.swift:262` 硬编码），v2.3.1 误把 `scanForDevices(timeout: 10)` 当成连接超时，已恢复 |
| v2.3.4  | 2026-05-08 | 收紧包解析边界：简单包和 SecureEnvelope 不允许尾部多余字节；字符串按 UTF-8 字节安全截断；BatteryLevel 和数值字段按代码 clamp；nonce 重放记录跨短期重连保留；App 分包重组限制未完成消息数 |
| v2.3.5  | 2026-05-08 | 补充第一次联调阅读入口、BLE 广播要求、Type 按方向解释规则、分包无 ACK 边界、坏包处理建议、WheelSelect / EnterTaskIn 用户动作边界；标明 Spectra 6 图片帧不属于第一轮联调 |
| v2.4.0  | 2026-05-29 | 联调修订（基于 `ble_log` 真机日志）：Sync 触发节流由「RequestRefresh 2s」改为「RequestRefresh/DeviceWake 共用 10s」（§8.5）；自动重连改用 CoreBluetooth pending connection 并区分主动/意外断开（§8.1）；新增 §8.7 记录固件实现偏差（DayPack 字符串字段被当作定长数值解析、`0x01`/`0x20` 入站命令未实现）。**协议规格本身未变，§8.7 为固件需对照修正项** |
| v2.4.1  | 2026-05-30 | 修正 Sync 触发节流（§8.5）：`RequestRefresh`(`0x20`) 改用**独立 2 秒闸**，`DeviceWake`(`0x30`) 继续用**独立 10 秒闸**；两者不再互相消耗配额（0x20 不再被频繁 0x30 饿死），被节流时均记录日志。撤回 v2.4.0 的「共用 10s」。协议字节不变 |
| v2.5.0  | 2026-05-31 | **DayPack 显示模型重写（破坏性）**：硬件实机 UI 实为「常驻宠物气泡 + 可换数据面板」，而非旧「4 页各说一句」。§4.7 将宠物文本收敛为单字段 `PetDialogue`（= App `currentPetDialogue` 同源，按时段自动变脸，早上即早安、傍晚即结算语），删除 `MorningGreeting / DailySummary / FirstItem / CurrentScheduleSummary / CompanionPhrase` 及 `SettlementData` 的 `SummaryMessage / EncouragementMessage`；新增带描述的 `Events[]`（旧协议缺）。§6 重写为「1 框架 + 面板」。固件需按新布局重写解析（与 §8.7 一并做）。设计论证见 §6.5 |
| v2.5.1  | 2026-06-02 | 文档补充：§4.12 增加 CustomAvatarFrame(`0x15`) 的 **App 侧重发策略**（退避降频：前 5 轮 sync 每轮重发、之后每 20 轮一次、**永不永久放弃**、成功推送或切换伴侣后清零）；§8.4 重试表加对应行。修复了原「硬上限 5 次后永久停发」会在硬件临时不可用时把待推头像永久搁置的缺陷。**wire 协议字节不变**，纯 App 侧重发行为 + 文档 |
| v2.5.2  | 2026-06-12 | App 侧健壮性修订（架构审计落地，wire 协议字节不变）：§3.2 **BLE 断连时 App 清空全部未完成分包重组状态**（修复 8 槽被脏断连残留占满后静默丢弃后续分包消息的缺陷），槽满丢弃记日志（按 MessageId 去重）；§9.5 明确离线回放补记任务完成时只应用状态变更，不触发声音/震动/俳句等实时反馈 |
| v2.5.3  | 2026-06-25 | **§10.4 帧缓冲表更正 7.3 寸为 1600×1200（4:3）**（原误为 800×480），缓冲区 192,000 → 960,000 bytes。仅文档修正，**wire 协议字节不变**。4 寸（400×600）未定，不动。详见硬件需求文档 v0.5 / 固件规格 v1.5.0 |
| v2.5.4  | 2026-06-28 | **FocusStatus(`0x14`) 字段语义修订（wire 字节不变，含义变）**：`ElapsedTime` 从「本会话累计专注分钟」改为「**当前未打断连续段**的专注分钟」——被手机打断即归零重计，用于驱动端上「装填进度条」在打断时归零；`Bottles` 改为按未打断段各自 floor(段÷30) 累计、零头不跨打断合并（满 30 分钟连续专注收 1 瓶，与 App 结算口径一致）。**固件若用 `ElapsedTime` 显示「总专注时长」会被打破，需对齐为「当前段」语义**（如固件仍需总时长，与 App 商定新增独立字段）。详见 §4.11。**（注：本条已被 v2.5.5 修订，勿按本条实现）** |
| v2.5.5  | 2026-06-28 | **FocusStatus(`0x14`) 改用「加字段」而非「原地改语义」（采纳协议演进最佳实践，修订 v2.5.4）**：撤回 v2.5.4 把 `ElapsedTime` 原地改成「当前段分钟」的做法——`ElapsedTime` **还原**为「本会话累计已专注分钟」（墙钟、不随打断归零，**不破坏**可能已按总时长实现的固件）；**新增 `SegmentMinutes`(2B BE)** 表示「当前未打断段分钟」（驱动装填、打断归零），**追加在变长 TaskTitle 之后**——旧固件读到 TaskTitle 即止、忽略尾部 2 字节（前向兼容），新固件多读 2 字节。`Phase` 明确为按当前未打断段计（打断退回 warmup）。`Bottles` 维持 v2.5.4 的按段累计。详见 §4.11 |
| v2.5.6  | 2026-06-28 | **`Mood`/`PetMoodByte` 固件处理约定（wire 字节不变，纯约定补充）**：明确 `PetStatus(0x01).Mood`（§4.2）与 `SmartReminder(0x13).PetMoodByte`（§4.10）——App **持续下发真实心情值**（H/E/F/S/M），但**固件当前阶段应忽略、不要据此展示或换图**；该字节作为**前向兼容通道保留**，待产品确定心情展示方案后再与 App 对齐渲染，无需 App 改版。背景：客户保留 App 端心情计算，硬件侧是否展示暂不确定，故先留通道、固件暂不消费 |
| v2.5.7  | 2026-06-28 | **DayPack 新增 `DaySummary` 字段（页面一框②「一天总结」，前向兼容追加）**：在 §4.7 payload **末尾**追加 `DaySummary`（≤180B，1B 长度前缀 + UTF-8），承载设计稿页面一框②——情绪向、**只谈日程**（不含 to-do 任务）的一天概览 + 一条实用建议（如「11:30 先休息，避开正午会议」），与 `PetDialogue`（宠物口吻单句）**互补**。`DaySummary` 是 DayPack 最后一个必读字段；按 §7.1 严格解析，固件须读取它才到 payload 末尾。无兼容风险是因为固件 DayPack 解析尚未上线、将按含它的完整布局实现。App 侧 `DayPackGenerator` 喂**今日事件明细（时间/标题）**经 LLM 生成，无 key/离线兜底为计数模板。**这是对 v2.5.0「单气泡」的补充而非回退**：宠物口吻仍是单句 `PetDialogue`，框②是独立的面板概览文本。详见 §4.7 / §6.5 |
| v2.5.8  | 2026-06-29 | **DayPack 新增 `FirstUp` 字段（页面一框③「First up」）**：在 `DaySummary` 之后再追加 `FirstUp`（≤60B，1B 长度前缀 + UTF-8），承载设计稿框③——下一个未来事件「HH:mm 标题」（全天仅标题），无未来事件则置顶（最高优先级未完成）任务标题，皆无则空串。**App 算好下发**（沿用 §6.5「App 是显示决策方」：相对当前时刻的「下一个」是 App 侧时间逻辑，固件只渲染）。`FirstUp` 现为 DayPack **最后一个字段**，同 §7.1 严格解析须读完它才到 payload 末尾——仿真解码器 `parseDayPack` 已同步。详见 §4.7 |
| v2.5.9  | 2026-06-29 | **Weather(`0x04`) 新增 `HighTemp` / `LowTemp`（页面一顶栏高/低温）**：在 §4.5 `Condition` 之后追加 `HighTemp`+`LowTemp`（各 1B 有符号 int8 摄氏度），承载设计稿顶栏「高/低温」（如「42/23」）；`Temperature` 仍为当前温度、语义不变。固件须读完这两字节才到 payload 末尾（严格解析）；若此前 0x04 仅读 temp+condition 需更新——仿真解码器 `parseWeather` 已同步。详见 §4.5 |
| v2.5.10 | 2026-06-29 | **Screensaver(`0x16`) 新增——屏保金句/明信片从开发命令升级为业务帧**：旧 `0xAA 01 02` 屏保命令仅 dev 模式可发，App 配置 `BLE_SHARED_SECRET`（secure）后被禁用、屏保静默发不出；v2.5.10 改用标准业务帧 `0x16`（经 SecureEnvelope，**dev/secure 均可发**），旧命令从 App 移除、固件无需实现。§4.1 加 `0x16` 行、新增 §4.15、§4.14 屏保块标废弃。场景解锁 `0xAA 01 01`（§4.14）未一并升级（独立 gamify 命令，同类隐患，需要时同法升级）。**App 侧已实现并全绿（467 tests）**，固件按 §4.15 实现 `0x16` 解析 |
| v2.5.11 | 2026-06-29 | **SceneUnlock(`0x17`) 新增——场景解锁从开发命令升级为业务帧（同 v2.5.10 屏保）**：旧 `0xAA 01 01` 场景解锁命令仅 dev 模式可发，secure 下被禁用、场景切换静默失败（生产 gamify 解锁 + 设置页选场景都受影响）；v2.5.11 改用标准业务帧 `0x17`（payload=1B SceneId，经 SecureEnvelope，**dev/secure 均可发**）。**至此两条 `0xAA` 开发显示命令全部退役**——App 出站不再产生任何 `0xAA`，相关死代码（`buildSceneUnlockPacket` / `writeDevelopmentDisplayPacket` / 仿真 `parseDevelopmentDisplayPacket`）已移除；§4.14 整节标废弃、新增 §4.16、§4.1 + §2.4 表加 `0x17`。固件按 §4.16 实现 `0x17` 解析 |
| v2.5.12 | 2026-06-29 | **§4.15 澄清屏保帧分包行为（纯文档，wire 不变）**：原写「payload 小，不分包」不准确——屏保 payload 最大约 225B（Quote≤180 + Author≤40 + 5B 头），`Quote`/`Author` 较长或 secure 封装（外层 `0x7E`）后可能超过协商 MTU 写长度，`shouldUseChunkedPacket`（`payloadSize+3 > maxWriteLength`）会触发 §3.2 分包。改为明确：屏保帧**可能单包亦可能分包**，固件须按通用分包重组、不可假设恒为单包。Codex 审查发现。§4.16 SceneUnlock（1B payload）恒为单包、不受影响 |
| v2.5.13 | 2026-06-30 | **新增 §6.6 字体与排版（纯文档，wire 不变）**：硬件内置两套字库，按**字段语义角色**渲染——`PetDialogue`（宠物气泡）用 Lugrasimo 手写体、其余**所有**中性/数据文本（天气/日期/事件卡/DaySummary/进度/TaskInPage/屏保等）用 Calibri。**字体不走 wire、App 不下发字体选择字节**（字段身份即字体选择器，沿用 §6.5 内容/呈现分离原则）；固件按字段映射字体 + 对 Lugrasimo 缺失字形回退 Calibri。明确「不逐串传字体、不加字体字节」（YAGNI）。回答客户「字体要不要走协议」：不要 |
| v2.5.14 | 2026-07-01 | **§3.5 补记出站 ASCII 净化保证（纯文档，wire 不变）**：App 在编码边界（`appendString` 单一咽喉点）把**所有**出站字符串字段净化为纯可打印 ASCII（`0x20`–`0x7E`）——LLM 常见的弯引号 `’ “ ”` / 长破折号 `— –` / 省略号 `…`、用户手输或日历同步带入的 emoji / 重音字母 / CJK，转写为 ASCII 近似（弯引号→直引号、破折号→`-`、`…`→`...`、`café`→`cafe`）或直接丢弃（无 ASCII 近似者）。**固件收到的任何文本字段恒为纯可打印 ASCII**，§6.6 的 Lugrasimo 缺字回退随之从常态降级为兜底安全网。修复起因：LLM 在 `DaySummary` 写出弯引号 U+2019（UTF-8 `E2 80 99`）→ 硬件渲染成豆腐块 `□`。同时**记 `RequestRefresh(0x20)` 联调期去抖合并**（§8.5）：固件把 0x20 当 ~2s 心跳狂发，App 改用 60s 合并窗把整轮 sync 去抖为 ≤1 次/分（不再硬抑制、保留用户物理刷新；固件停止心跳后按键即时触发）。均为 App 侧行为、wire 不变。ASCII 修复经 Claude 编排研究 + Codex(gpt-5.5) 联合 review：净化器本体 airtight，Codex 补捉 `Schedule(0x03)` `StartTime` 的 `DateFormatter` 缺 `en_US_POSIX` locale（波斯/阿拉伯数字区会输出非 ASCII 数字、打偏固定 5 字节字段）——已修 |
| v2.5.15 | 2026-07-02 | **§6.7 新增——面板态判定拍板（纯文档，wire 不变）**：关闭 §6.5 提案要点第 3 条开放问题——**不新增 `PanelMode` 字节**，态 A/B/C 由固件本地状态机判定（本地 RTC + 已收数据 + 用户按键），App 只负责内容与校时。判定优先级：专注中→态 C；有未完成任务→态 B；有事件→态 A；全空→固件空态兜底。原「App 是显示决策方」语义修正为「App 决定**内容**、固件决定**时机与状态**」。依据行业同类分工（Pebble Timeline / BLE CTS / InfiniTime——手机只推结构化数据与时间，屏幕状态是设备本地状态机）；§6.6 早前已按「不引入 PanelMode」行文，本次正式落笔。边界值（晚间结算时段、进行中事件窗口）标注待与固件定稿 |
| v2.5.16 | 2026-07-03 | **§8.5 补记 Time→0x20 反射回路与 DayPack 双发（纯文档 + App 行为，wire 不变）**：联调实测（MsgID 连号、间隔 ~3s、除 PetDialogue/时间外相同的两个完整 DayPack）——固件每收到 `Time(0x05)` 即回一个 `RequestRefresh(0x20)`，而 Time 是 App 每轮 sync 的第一帧，该反射经 App「在途 sync 期间收到的 force 请求收尾补跑」机制放大为背靠背第二轮；恰逢 LLM 对话在两轮之间生成完成（~3s），PetDialogue 变化令 DayPack 指纹变化、第二轮真发 DayPack、硬件双刷屏。**App 侧已修（build 589）**：sync 组包前等待在途对话生成完成（首轮即最终文本），反射补跑轮因内容无变化不再携带 DayPack（退化为 Time/PetStatus 小帧）。**固件侧建议**：收到 Time 不要触发 0x20——0x20 仅保留「开机/唤醒后久无数据」与「用户物理按键刷新」两种意图；7.3寸全刷 ~12s，渲染进行中收到新 DayPack 应合并到下一次刷新而非排队双刷。**§4.7 补记 TopTasks 实现对齐**：规格上限一直是 4寸≤3 / 7.3寸≤5（未变），但 App 端生成与编码此前固定按 4 寸档发 ≤3 条，7.3 寸设备只收到 3 条置顶任务；build 589 起按 App Settings→Hardware Details 配置的屏型发满上限（设备暂无屏型自报通道，需在 App 内手动选择一次），同优先级任务截取顺序确定化（priority→dueDate→id）。wire 格式不变 |

### 1.4 术语表

| 术语 | 定义 |
|---------------|------------------------------------------------------|
| Day Pack      | 发送至设备的完整每日数据包 |
| Event Log     | 从设备发送至 App 的用户交互事件 |
| Task In       | E-ink 显示屏上的任务详情页 |
| Settlement    | 每日结算总结页 |
| Focus Mode    | 减少干扰的简化显示模式 |
| Encoder Knob  | 带按压按钮的旋转编码器，用于导航 |
| SecureEnvelope | v2 安全封装，包含 nonce、timestamp、HMAC-SHA256 |

---

## 2. BLE 配置

### 2.1 Service UUID

```
Service UUID: 0000FFE0-0000-1000-8000-00805F9B34FB
```

**广播要求：** 设备广播包必须包含 Service UUID `0000FFE0-0000-1000-8000-00805F9B34FB`。App 当前只扫描带这个 Service UUID 的外设；如果固件只广播设备名、不广播该 Service UUID，App 将搜不到设备。

### 2.2 Characteristics

| Characteristic | UUID                                   | 方向 | 属性 |
|----------------|----------------------------------------|----------------|-----------------|
| Write          | `0000FFE1-0000-1000-8000-00805F9B34FB` | App → Device   | Write           |
| Notify         | `0000FFE2-0000-1000-8000-00805F9B34FB` | Device → App   | Notify          |

### 2.3 连接参数

| 参数 | 值 |
|--------------------|------------|
| Scan Timeout       | 10 秒（`BLEService.scanForDevices(timeout:)` 默认参数） |
| Connection Timeout | 15 秒（`BLEService.swift:262` 硬编码 `Task.sleep(for: .seconds(15))`，连接成功前未收到 didConnect 即视为超时） |
| 自动重连 | 启用 |

### 2.4 Type 字节按方向解释

`Type` 字节必须先看方向，再解释含义。固件不能只按 `Type` 判断业务含义。

| 方向 | Characteristic | 解释规则 |
|------|----------------|----------|
| App → Device | `FFE1` Write | 使用第 4 节 App → Device 命令表 |
| Device → App | `FFE2` Notify | 使用第 5 节 Device → App 事件表 |

容易混淆的复用值：

| Type | App → Device | Device → App |
|------|--------------|--------------|
| `0x10` | DayPack | EnterTaskIn |
| `0x11` | TaskInPage | CompleteTask |
| `0x12` | DeviceMode | SkipTask |
| `0x13` | SmartReminder | SelectedTaskChanged |
| `0x14` | FocusStatus | WheelSelect |
| `0x15` | CustomAvatarFrame | ViewEventDetail |
| `0x16` | Screensaver | ReminderAcknowledged |
| `0x17` | SceneUnlock | ReminderDismissed |
| `0x20` | EventLogRequest | RequestRefresh |
| `0x21` | 暂无 App 出站业务使用 | EventLogBatch |

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

**长度规则：** App→Device 简单包必须满足 `packet.count == 3 + Length`。Device→App 简单事件包必须满足 `packet.count == 2 + Length`。尾部多余字节视为格式错误，不参与解析。

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

**联调边界：** 分包总数上限为 255。App 侧最多同时保留 8 个未完成 MessageId，单个重组 payload 上限 256 KiB；超过限制的分包会被丢弃（v2.5.2 起丢弃会记 App 侧日志，按 MessageId 去重）。**BLE 断连时 App 清空全部未完成重组状态**（v2.5.2）——固件重连后用新 MessageId 重发即可，不会撞上断连前残留的半成品槽位。接收端也应做超时和容量上限，避免丢包后长期占用内存；App 侧当前只验证每包 CRC 和完整重组，不发送分包级 ACK。

**丢包处理：** 当前 App 不支持分包 ACK，也不支持单个分包重传。固件接收 App 分包时，如果 CRC 错、长度错、超时或缺包，应丢弃整条未完成消息，等待 App 后续重新发送完整消息。

### 3.3 安全握手（v2）

当 App 配置了 `BLE_SHARED_SECRET` 时，连接后必须先完成安全握手，握手命令类型为 `0x7F`，未通过握手不得进入业务通信。  
当未配置密钥时，App 进入 MVP 兼容模式，可直接使用旧协议明文通信用于联调。

第一次硬件联调使用的 App 包如果未配置 `BLE_SHARED_SECRET`，固件先实现明文协议，不需要实现 HMAC 握手。安全握手作为第二阶段联调内容。

- `ClientHello`：`kind(0x01) + clientNonce(8B) + timestamp(4B) + hmac(32B)`
- `ServerHello`：`kind(0x02) + clientNonce(8B) + serverNonce(8B) + timestamp(4B) + hmac(32B)`
- `hmac` 算法：`HMAC-SHA256`
- 时间窗口：±120 秒

### 3.4 SecureEnvelope（v2）

当 App 配置了 `BLE_SHARED_SECRET` 时，业务 payload 必须封装为 `SecureEnvelope`，外层命令类型固定 `0x7E`：

`version(1B=2) + payloadType(1B) + nonce(8B) + issuedAt(4B) + payloadLen(2B) + payload(NB) + signature(32B)`

- `signature = HMAC-SHA256(version..payload)`  
- 接收端必须校验签名、时间窗口和 nonce 重放。
- `payloadLen` 后必须正好是 `payload(NB) + signature(32B)`，尾部多余字节视为格式错误。
- App 侧 nonce 重放记录会在 ±120 秒窗口内保留，短时间断开重连后仍拒绝刚收到过的 secure payload。

### 3.5 字符串编码

字符串使用长度前缀编码：

```
+--------+------------------+
| Length | UTF-8 Data       |
| 1 byte | N bytes          |
+--------+------------------+
```

- **编码方式：** UTF-8
- **最大长度：** 按字段指定，单位是 UTF-8 字节，不是字符数
- **Length 字节：** 实际字节数（非字符数）
- **截断规则：** App 截断字符串时不会切断 UTF-8 字符；如果最大字节数落在多字节字符中间，会回退到上一个完整 UTF-8 字符边界。
- **字符集：仅可打印 ASCII `0x20`–`0x7E`（v2.5.14 新增，App 侧保证）。** App 在编码边界（`appendString` 单一咽喉点）统一净化所有出站字符串字段，**保证只含可打印 ASCII**。非 ASCII 字符——LLM 常吐的弯引号 `’ ‘ “ ”`、长破折号 `— –`、省略号 `…`、不间断空格；用户手输或日历同步带入的 emoji、重音字母、CJK 等——在下发前被**转写为 ASCII 近似**（弯引号→`'`/`"`、破折号→`-`、`…`→`...`、`café`→`cafe`、全角→半角）或**直接丢弃**（emoji / CJK / 货币 / 数学符等无 ASCII 近似者）。因此**固件收到的任何文本字段都是纯可打印 ASCII，无需处理多字节 UTF-8 排版字符，也不会出现「豆腐块」`□`**。此为 App 侧保证，wire 格式不变（ASCII 是 UTF-8 子集，`Length` 仍是字节数）；固件字库只需覆盖 `0x20`–`0x7E`（见 §6.6 缺字回退已降级为兜底安全网）。

### 3.6 字节序

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
| `0x14` | FocusStatus  | App→Device 推送当前专注状态与能量瓶子数（所有构建均执行） |
| `0x15` | CustomAvatarFrame | ⚠️ 待对齐：推送用户自定义伴侣的 96×96 Spectra 6 像素帧（详见 §4.12） |
| `0x16` | Screensaver  | 屏保金句/明信片业务帧（替代旧 `0xAA 01 02` 开发命令，secure 模式可发；详见 §4.15） |
| `0x17` | SceneUnlock  | 场景解锁业务帧（替代旧 `0xAA 01 01` 开发命令，secure 模式可发；详见 §4.16） |
| `0x20` | EventLogRequest | 请求指定时间戳之后的事件日志 |
| `0x7E` | SecureData | 安全业务封装（v2） |
| `0x7F` | SecurityHandshake | 安全握手（v2） |

---

### 4.2 PetStatus (0x01)

用于显示的宠物状态信息。

**Payload 结构：**

| Offset | Field       | Size        | Max Length | 描述 |
|--------|-------------|-------------|------------|--------------------------------|
| 0      | Name        | 1 + N bytes | 20 bytes   | 显示名（长度前缀） |
| N+1    | Mood        | 1 byte      | -          | 心情首字母 ASCII |
| N+2    | CharacterId | 1 + N bytes | 10 bytes   | 伴侣 IP：`joy` / `silas` / `nova` |

**CharacterId 值：**

| Value   | 说明 |
|---------|------|
| `joy`   | Joy（喜乐） |
| `silas` | Silas（仁爱） |
| `nova`  | Nova（节制 / 自律） |

**Mood 值：**

| Value | Mood        |
|-------|-------------|
| `H`   | Happy       |
| `E`   | Excited     |
| `F`   | Focused     |
| `S`   | Sleepy      |
| `M`   | Missing You |

> **固件处理约定（v2.5.6，wire 字节不变）：** App **持续下发真实心情值**（上表 H/E/F/S/M，由任务进度 / 时段 / 陪伴间隔实时计算）。但**是否据此在硬件上展示或切换形象，由产品后续确定**——**固件当前阶段应忽略 `Mood` 字节，不要假设其展示语义、不要据它换图**。该字节作为前向兼容通道保留：待产品拍板启用后，再与 App 对齐渲染规则，无需 App 改版。`SmartReminder(0x13)` 的 `PetMoodByte`（§4.10）适用同一约定。

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
| 0      | Title       | 1 + N bytes | 30 bytes   | 任务标题 |
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
| 0      | Title     | 1 + N bytes | 25 bytes   | 事件标题 |
| N+1    | StartTime | 5 bytes     | -          | "HH:mm" 格式（原始 UTF-8） |

---

### 4.5 Weather (0x04)

当前天气信息。

**Payload 结构：**

| Offset | Field       | Size        | Max Length | 描述 |
|--------|-------------|-------------|------------|--------------------------|
| 0      | Temperature | 1 byte      | -          | 有符号 int8（摄氏度），**当前温度** |
| 1      | Condition   | 1 + N bytes | 15 bytes   | 天气状况字符串 |
| ...    | HighTemp    | 1 byte      | -          | 有符号 int8（摄氏度），当日**最高温**（v2.5.9，在 Condition 后追加）|
| ...    | LowTemp     | 1 byte      | -          | 有符号 int8（摄氏度），当日**最低温**（v2.5.9，在 HighTemp 后）|

> **v2.5.9 追加（HighTemp / LowTemp）**：在 `Condition` 之后追加 `HighTemp` + `LowTemp`（各 1 字节有符号 int8，摄氏度），承载顶栏「高/低温」显示（设计稿如「42/23」）。`Temperature` 仍是**当前温度**、语义不变。按 wire 严格解析约定，固件须读完这两字节才到 payload 末尾；若固件此前已实现 0x04 仅读 `Temperature`+`Condition`，需更新为读到 `LowTemp`（仿真解码器 `parseWeather` 已同步）。

**Condition 值：**

| Value             | 描述 |
|-------------------|-------------|
| `sun.max.fill`    | 晴天 |
| `cloud.fill`      | 多云 |
| `cloud.sun.fill`  | 局部多云 |
| `cloud.rain.fill` | 雨天 |
| `cloud.snow.fill` | 雪天 |
| `cloud.bolt.fill` | 暴风雨 |

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

设备「概览」帧的完整每日数据包（对应 §6 的常驻框架 + 数据面板）。专注态（态 C）**不在此包内**，由 `0x11 TaskInPage` + `0x14 FocusStatus` 驱动。

**Payload 结构（v2.5.0 重写 — 破坏性，见 §6.5）：**

| Offset | Field                  | Size        | Max Length | 描述 |
|--------|------------------------|-------------|------------|--------------------------------|
| 0      | Year                   | 1 byte      | -          | 年份 - 2000 |
| 1      | Month                  | 1 byte      | -          | 月份（1-12） |
| 2      | Day                    | 1 byte      | -          | 日期（1-31） |
| 3      | DeviceMode             | 1 byte      | -          | 0x00=Interactive, 0x01=Focus |
| 4      | FocusChallengeEnabled  | 1 byte      | -          | 0x00=禁用, 0x01=启用 |
| 5      | PetDialogue            | 1 + N bytes | 120 bytes  | **宠物气泡**：= App `currentPetDialogue`（阶段感知，早安/陪伴/结算同一句变脸，见 §6.5）|
| ...    | EventCount             | 1 byte      | -          | 今日事件数（0-N）|
| ...    | Events[]               | Variable    | -          | 事件列表（见下「Event 条目」）|
| ...    | TaskCount              | 1 byte      | -          | 置顶任务数量（0-5，取决于屏幕尺寸）|
| ...    | TopTasks[]             | Variable    | -          | 置顶任务（见下，4寸≤3 / 7.3寸≤5）|
| ...    | SettlementData         | Variable    | -          | 进度/专注数值（见下，**已无文本消息**）|
| ...    | DaySummary             | 1 + N bytes | 180 bytes  | **一天总结（框②）**：情绪向、**只谈日程**（不含 to-do 任务）的概览 + 一条实用建议；追加在 `SettlementData` 之后（v2.5.7，见下注）。空串表示尚未生成 |
| ...    | FirstUp                | 1 + N bytes | 60 bytes   | **下一项（框③）**：「First up:」内容——下一个未来事件「HH:mm 标题」（全天事件仅标题），无未来事件则置顶任务标题，皆无则空串。App 算好下发；**DayPack 当前最后一个字段**（v2.5.8，在 DaySummary 之后，见下注）|

> **v2.5.0 破坏性变更**：删除旧字段 `MorningGreeting / DailySummary / FirstItem / CurrentScheduleSummary / CompanionPhrase`，收敛为单字段 `PetDialogue`；新增带描述的 `Events[]`（旧协议缺此能力）。固件解析器须按本表重写。

> **v2.5.7 追加（新增字段，严格解析）**：在 payload **末尾**追加 `DaySummary`（框②「一天总结」，≤180 字节，1 字节长度前缀 + UTF-8）。注意：按 §7.1，wire 解析是**严格**的（尾部多余字节视为格式错误），故 `DaySummary` 是 DayPack 的**尾部必读字段**（其后还有 `FirstUp`，v2.5.8）、不是可忽略的可选尾巴，固件须按顺序读完尾部字段才算到达 payload 末尾。无兼容风险是因为**固件 DayPack 解析尚未上线**——会直接按含 `DaySummary` 的完整 v2.5.7 布局实现；置于定长 `SettlementData` 之后只是让既有字段偏移保持稳定。语义：与 `PetDialogue`（宠物口吻单句）**互补**——`DaySummary` 是**面板上的一天概览段落**，情绪向、只谈日程、附一条实用建议（如「11:30 先休息，避开正午会议」）。App 侧由 `DayPackGenerator` 喂**今日事件明细（时间/标题）**经 LLM 生成，无 key/离线时兜底为「N events today」计数模板。背景见 §6.5（v2.5.0 曾把多段文本收敛为单气泡，框②的一天总结此次作为**面板文本字段**复活，不回退单气泡决策）。

> **v2.5.8 追加（FirstUp，框③）**：在 `DaySummary` **之后**再追加 `FirstUp`（≤60 字节，1 字节长度前缀 + UTF-8），承载设计稿页面一框③的「First up:」内容。值由 **App 算好下发**：取**下一个未来事件**（startTime > 当前时刻、最早的一个）格式化为「HH:mm 标题」（全天事件仅标题）；无未来事件则取**置顶（最高优先级未完成）任务**标题；皆无则空串。由 App 算而非固件合成，是沿用 §6.5「App 是显示决策方」——「相对当前时刻的下一个」是 App 侧时间逻辑，固件只渲染。`FirstUp` 现为 DayPack **最后一个字段**，同 §7.1 严格解析：固件须读完它才到 payload 末尾（仿真解码器 `parseDayPack` 已同步）。

**Event 条目：**

| Offset | Field       | Size        | Max Length | 描述 |
|--------|-------------|-------------|------------|--------------------------|
| 0      | Time        | 1 + N bytes | 8 bytes    | 起始时间 "HH:mm"（全天事件为空串）|
| ...    | Title       | 1 + N bytes | 40 bytes   | 事件标题 |
| ...    | Description | 1 + N bytes | 120 bytes  | 事件描述（设计稿事件卡正文）|

**TopTask 条目：**

| Offset | Field          | Size        | Max Length | 描述 |
|--------|----------------|-------------|------------|--------------------------|
| 0      | TaskId         | 1 + N bytes | 36 bytes   | UUID 字符串 |
| N+1    | Title          | 1 + N bytes | 30 bytes   | 任务标题 |
| ...    | IsCompleted    | 1 byte      | -          | 0x00=未完成, 0x01=已完成 |
| ...    | Priority       | 1 byte      | -          | 优先级（1-3） |

> **v2.5.16 实现对齐（wire 不变）**：TopTasks 上限规格一直是 4寸≤3 / 7.3寸≤5，但 App 端生成与编码此前固定按 4 寸档发 ≤3 条——7.3 寸设备只收到 3 条置顶任务（2026-07-03 联调实测）。App build 589 起按 **Settings → Hardware Details → E-ink Screen Size** 配置的屏型发满上限（设备暂无屏型自报通道，需在 App 内手动选择一次）；同优先级任务的截取顺序确定化（priority 降序 → dueDate 升序 → id），wire 上的任务次序可复现。

**SettlementData：**

| Offset | Field               | Size        | Max Length | 描述 |
|--------|---------------------|-------------|------------|--------------------------|
| 0      | TasksCompleted      | 1 byte      | -          | 已完成任务数（clamp 0-255） |
| 1      | TasksTotal          | 1 byte      | -          | 总任务数（clamp 0-255） |
| 2      | PointsEarned        | 2 bytes     | -          | 积分（Big Endian，clamp 0-65535） |
| 4      | TotalFocusMinutes   | 2 bytes     | -          | 总专注时间（分钟，Big Endian，clamp 0-65535） |
| 6      | FocusSessionCount   | 1 byte      | -          | 专注会话次数（clamp 0-255） |
| 7      | LongestFocusMinutes | 2 bytes     | -          | 最长单次专注时间（分钟，BE，clamp 0-65535） |
| 9      | InterruptionCount   | 1 byte      | -          | 专注期间手机解锁次数（clamp 0-255） |

> **v2.5.0**：删除 `SummaryMessage` / `EncouragementMessage`——宠物口吻统一由顶层 `PetDialogue` 承载。SettlementData 现仅含上述定长数值字段（供进度条与专注指标展示）。能量瓶子数经 `0x14 FocusStatus` 实时推送，不在 DayPack 内。

**解析说明（重要，固件必读）：**

- **Offset 列的 `...` 表示偏移随变长字段累积，不是固定偏移。** `N` 不是常量，指紧邻前一个变长字符串的实际内容字节数；从 `PetDialogue`(offset 5) 起整个 payload 都是变长流（含 `Events[]` / `TopTasks[]` 子结构）。
- 固件**必须顺序流式解析**：读 1 字节长度 → 读对应字节数内容 → 指针前进；**不能 seek 到硬编码偏移**。（§8.7「问题 1」的字段错位正源于此。）
- 上表所有字段在每个 DayPack 中**按序存在、无条件写入**；"空"只是长度为 0、仍占位，不会被省略或跳过：
  - 空字符串 = 单字节 `0x00`（例如无日程时 `CurrentScheduleSummary`，见 §7.1 测试向量）。
  - `TopTasks` 为 0 条时 `TaskCount = 0x00`，其后**没有**任何 TopTask 子结构。
  - `SettlementData` 的定长字段恒在，`SummaryMessage` / `EncouragementMessage` 可为空串。
- **关键**：不能因为某字段值为空，就不读它的长度字节 / 计数字节——那 1 个字节始终占位，少读一字节即整体错位。

---

### 4.8 TaskInPage (0x11)

任务详情页数据（页面 3）。

**Payload 结构：**

| Offset | Field                | Size        | Max Length | 描述 |
|--------|----------------------|-------------|------------|--------------------------|
| 0      | TaskId               | 1 + N bytes | 36 bytes   | UUID 字符串 |
| N+1    | TaskTitle            | 1 + N bytes | 40 bytes   | 任务标题 |
| ...    | TaskDescription      | 1 + N bytes | 100 bytes  | 任务描述 |
| ...    | Encouragement        | 1 + N bytes | 50 bytes   | 鼓励消息 |
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
| 0      | ReminderText | 1 + N bytes | 60 bytes   | 提醒消息文本 |
| N+1    | ReminderType | 1 byte      | -          | 0x00=gentle, 0x01=urgent |
| N+2    | PetMoodByte  | 1 byte      | -          | 显示用宠物心情（ASCII: H/E/F/S/M） |

**ReminderType 值：**

| Value  | Name          | 描述 |
|--------|---------------|------------------------------------------|
| `0x00` | Gentle        | 普通提醒，标准显示 |
| `0x01` | Urgent        | 紧急提醒，加粗边框显示 |

> **`PetMoodByte` 固件处理约定（v2.5.6）：** 同 §4.2 `Mood` 字节——App 持续下发真实心情值，但**固件当前阶段应忽略、不要据此展示或换图**，作为前向兼容通道保留，待产品启用后再对齐渲染。

**设备行为：**
- 在当前页面上显示横幅覆盖层
- 无用户交互时 10 秒后自动消失
- 任意按钮按下立即消失
- 向 App 发送 ReminderAcknowledged (0x16) 或 ReminderDismissed (0x17) 事件

---

### 4.11 FocusStatus (0x14)

App→Device 实时推送当前专注状态与能量瓶子数。在所有构建（Debug 和 Release）中，只要 BLE 已连接即执行；Debug 构建同时额外通过 `SimulatorBridge` 发送相同信息供模拟器显示。

`BLEDataType` enum 现已移至 `Core/BLE/BLEProtocol.swift`，该文件为出站协议字节的单一真相源。

**Payload 结构：**

| Offset | Field        | Size        | 描述 |
|--------|--------------|-------------|------------------------------------------------------|
| 0      | Phase        | 1 byte      | 专注阶段（按**当前未打断段**计，打断后退回 warmup）：0=idle, 1=warmup(0-5m), 2=building(6-15m), 3=deep(16m+) |
| 1      | Bottles      | 1 byte      | 本会话已收集的能量瓶子数：按未打断段各自 floor(段÷30) 累计，打断重置正在装填的进度、零头不跨打断合并（clamp 0-255） |
| 2      | ElapsedTime  | 2 bytes BE  | 本会话累计已专注分钟数（自进入任务，墙钟，**不**随打断归零；Big Endian UInt16，clamp 0-65535） |
| 4      | TaskTitle    | 1 + N bytes | 当前任务标题（长度前缀 UTF-8，最多 40 字节） |
| 4+1+N  | SegmentMinutes | 2 bytes BE | **当前未打断连续段**分钟数：被手机打断即归零重计，驱动端上「装填进度」。追加在 TaskTitle 之后，旧固件读到 TaskTitle 即止、忽略尾部字节（前向兼容）。Big Endian UInt16，clamp 0-65535 |

**Phase 值：**

| Value | Name     | 说明 |
|-------|----------|------|
| `0`   | idle     | 无活跃专注会话 |
| `1`   | warmup   | 当前未打断段 0-5 分钟 |
| `2`   | building | 当前未打断段 6-15 分钟 |
| `3`   | deep     | 当前未打断段 16 分钟以上 |

---

### 4.12 CustomAvatarFrame (0x15) ⚠️ 待硬件团队对齐

App→Device 推送用户自定义伴侣的像素帧：用户在 App 内选用自定义伴侣形象时，将其 96×96 图像推送到 E-ink 显示。**App 端已实现并在运行**（用户选择自定义伴侣、以及 BLE 重连补推时发送），但本命令尚未经硬件团队确认，固件侧需按本节实现接收。

**对齐事项：**

1. **字节复用（无需换字节，仅需确认）：** `0x15` 出站=CustomAvatarFrame、入站=ViewEventDetail（§5.11），这与本协议**既有规则完全一致**——`0x10`~`0x14`、`0x20` 等几乎所有低位字节都按方向双义（出站走 `FFE1` Write、入站走 `FFE2` Notify，方向天然区分、线上不冲突，另见 §2.4 复用值表）。因此**保留 `0x15`、不换字节**；固件只需像处理 `0x10`~`0x14` 那样**按方向 / 特征值分发**即可。仅当固件确实无法按方向分发（共用单一 opcode 表）时才需另议——但既然 `0x10`~`0x14` 已双义处理，通常无此必要。
2. **像素格式（⚠️ 唯一真正待拍板项）：** 当前 payload 为 4bpp packed（96×96 → 4608B）。固件需确认 **4bpp 的半字节→像素映射顺序** 与 **Spectra 6 调色板映射** 是否与此一致。`SubVersion` 字段用于格式演进，当前固定 `0x01`。

**传输方式：** 经 §3.2 分包帧发送（9 字节分包头，`type=0x15`）；固件按分包重组后得到下方完整 payload。**不以简单包形式出现。**

**重组后 Payload 结构：**

| Offset | Field      | Size      | 描述 |
|--------|------------|-----------|------|
| 0      | SubVersion | 1 byte    | 格式版本，当前固定 `0x01` |
| 1      | Width      | 1 byte    | 像素宽，当前 `0x60`(=96) |
| 2      | Height     | 1 byte    | 像素高，当前 `0x60`(=96) |
| 3      | Pixels     | N bytes   | 4bpp packed 像素数据，96×96 → 4608 字节 |

总 payload 长度典型为 `3 + 4608 = 4611` 字节。

**真相源：** 出站字节见 `Core/BLE/BLEProtocol.swift` 的 `BLEDataType.customAvatarFrame`；编码见 `BLEDataEncoder.encodeCustomAvatarFrame`。

**App 侧重发策略（联调相关，v2.5.1）：** 自定义头像帧由 App 在切换伴侣或 BLE 重连后尝试推送。若推送失败（硬件未就绪 / 固件尚未实现 `0x15`），App 会把该伴侣标记为待重发，并在后续每轮 sync 重试，采用**退避降频**而非固定次数硬上限：

- 前 5 轮 sync：每轮都重发（覆盖临时抖动，硬件恢复后快速补上）。
- 之后：每 20 轮 sync 才重发一次（固件长期不接受 `0x15` 时，不会每轮 sync 刷屏）。
- **永不永久放弃**：只要仍处待重发状态，就始终保留周期性重试；硬件一旦开始接受 `0x15` 即自愈。
- 成功推送、或用户切换到其它伴侣后，重试计数清零。

> 联调提示：固件未实现 `0x15` 期间，会看到 App 偶发重发一帧失败的 `0x15`——这是预期内的低频自愈重试，**不是 bug**；固件实现 `0x15` 后该帧即被接受、重发自然停止。真相源：`AppState+CustomCompanions.swift` 的 `shouldAttemptCustomAvatarFlush` / `flushPendingCustomCompanionPushIfNeeded`。

---

### 4.13 EventLogRequest (0x20)

App 请求设备回传增量 Event Log（用于断线重连后补齐事件）。

**Payload 结构：**

| Offset | Field | Size    | 描述 |
|--------|-------|---------|-------------------------------------------|
| 0      | Since | 4 bytes | Unix Timestamp（Big Endian，UInt32） |

**设备行为：**
- 查询本地环形缓冲中 `timestamp > Since` 的事件
- 按批次通过 EventLogBatch (0x21) 回传

---

### 4.14 开发显示命令（0xAA 前缀）— 已全部废弃

> **本节命令已全部升级为正式业务帧，`0xAA` 前缀不再使用。** 历史上场景解锁（`AA 01 01`）与屏保（`AA 01 02`）走 `0xAA` 开发命令，仅 dev 模式可达、配置 `BLE_SHARED_SECRET`（secure）后被禁用、生产下静默失败。现：
> - **场景解锁 → `0x17` 业务帧**（v2.5.11，见 **§4.16**）
> - **屏保金句/明信片 → `0x16` 业务帧**（v2.5.10，见 **§4.15**）
>
> 两者均改走标准 `Type + Length + Payload` 业务包、secure 模式可发；旧 `0xAA` 命令已从 App 移除，**固件无需实现任何 `0xAA` 命令**。若固件仍收到 `0xAA` 包，说明是过时 App，可安全忽略。

---

### 4.15 Screensaver (0x16)

App→Device 推送屏保金句 / 明信片。**v2.5.10 起为标准业务帧**（替代旧 §4.14 `0xAA 01 02` 开发命令）：经 `Type + Length + Payload` 业务包发送，secure 模式自动经 SecureEnvelope（`0x7E`）封装，**dev / secure 两种模式均可发**——修复了旧开发命令在配置 `BLE_SHARED_SECRET` 后被禁用、屏保静默发不出的缺陷。

**Payload 结构：**

| Field | Size | Max | 描述 |
|-------|------|-----|------|
| ContentType | 1 byte | - | `0x00=normal`（金句）, `0x01=postcard`（明信片）|
| SceneByte | 1 byte | - | 场景：`0x00=harbor`, `0x01=forest`, `0x02=nightCity` |
| PostcardDay | 1 byte | - | 明信片天数，无则为 0 |
| QuoteLen + Quote | 1 + N bytes | 180 bytes | UTF-8 金句（1 字节长度前缀）|
| AuthorLen + Author | 1 + N bytes | 40 bytes | UTF-8 作者（1 字节长度前缀）|

> **传输：** payload 较短时走简单包 `Type(0x16) + Length + Payload`；但 Quote（≤180B）+ Author（≤40B）较长时，整体可能超过协商的 MTU 写长度，此时按 §3.2 **分包**（9 字节分包头），固件须按通用分包重组——**不可假设屏保帧恒为单包**。secure 模式下整体先由 `0x7E SecureData` 封装，再按需对**外层 `0x7E`** 分包。**真相源：** 出站字节见 `Core/BLE/BLEProtocol.swift` 的 `BLEDataType.screensaver`；编码见 `BLEDataEncoder.encodeScreensaver`；测试见 `BLESceneUnlockTests.screensaverFrameEncoding`。
>
> **场景解锁同样已升级**：场景解锁（旧 §4.14 `0xAA 01 01`）已于 v2.5.11 一并升级为 `0x17` 业务帧，见 **§4.16**。`0xAA` 开发命令已全部退役。

---

### 4.16 SceneUnlock (0x17)

App→Device 推送场景解锁 / 切换（gamify：用户专注攒能量瓶解锁 harbor / forest / nightCity，或在设置页手动切换）。**v2.5.11 起为标准业务帧**（替代旧 §4.14 `0xAA 01 01` 开发命令）：经 `Type + Length + Payload` 业务包发送，secure 模式自动经 SecureEnvelope（`0x7E`）封装，**dev / secure 两种模式均可发**——修复了旧开发命令在配置 `BLE_SHARED_SECRET` 后被禁用、场景切换静默失败的缺陷。

**Payload 结构：**

| Field | Size | 描述 |
|-------|------|------|
| SceneId | 1 byte | `0x00=harbor`, `0x01=forest`, `0x02=nightCity` |

> **传输：** 经简单包 `Type(0x17) + Length(=1) + SceneId` 发送；secure 模式整体由 `0x7E SecureData` 封装。**真相源：** 出站字节见 `Core/BLE/BLEProtocol.swift` 的 `BLEDataType.sceneUnlock`；编码见 `BLEDataEncoder.encodeSceneUnlock`；测试见 `BLESceneUnlockTests.sceneUnlockFrameEncoding`。

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
| `0x30` | DeviceWake          | 设备上线通知：BLE Notify 建立后固件主动上报（非 App 触发 MCU 唤醒） |
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
- 回发 TaskInPage (0x11) 包含任务详情
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
- 标记任务为已跳过，返回 Overview（概览页）
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

### 5.8 DeviceWake (0x30) — 设备上线通知 / Wake Notify

BLE Notify 特征开启后，固件**主动**向 App 发送此帧，表示「设备已上线」。

> **语义澄清**：此帧**不是 App 唤醒 MCU 的命令**，方向是 Device→App。MCU 何时从休眠中醒来由固件自行决定（RTC / 按键 / 电源事件等）。时序：MCU 唤醒 → 广播 → App 扫描连接 → GATT 发现 → 开 Notify → 固件发送此帧。

**Payload：**

| Offset | Field        | Size   | 描述 |
|--------|--------------|--------|-------------------------------|
| 0      | BatteryLevel | 1 byte | 当前电量百分比（App clamp 0-100） |

> **固件版本要求：** v2.3.0+ 起此 payload 为必填。旧固件若发送空 payload（Length = 0），App 将忽略电量更新，保持上次已知值。

**App 响应：**
1. 若 payload 非空：更新并显示设备电量。
2. 同步时间并发送更新数据。

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
- 第一轮联调不要用 `WheelSelect` 打开任务详情。
- 当前 App 仅记录/调试该事件，不回发 TaskInPage 或事件详情。
- 用户在设备上选中任务并进入详情页时，固件必须发送 EnterTaskIn (0x10)，App 才会回发 TaskInPage (0x11)。

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
| 0      | BatteryLevel | 1 byte | 电量百分比（App clamp 0-100） |

**App 响应：** 更新设备电量显示，并向用户推送低电量本地通知。

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
- `0x01~0x06`, `0x20`, `0x31`：无 payload（记录总长 1B）
- `0x30`：`BatteryLevel(1B)`（记录总长 2B，v2.3.0+）
- `0x40`：`BatteryLevel`（记录总长 2B）
- `0x16`, `0x17`：`Timestamp(4B)`（记录总长 5B）
- `0x10~0x12`：`Length(1B)+TaskId(NB)+Timestamp(4B)`（记录总长 `2+N+4`）
- `0x13~0x15`：`Length(1B)+Id(NB)`（记录总长 `2+N`）
- App 严格校验整批长度：必须正好解析出 `Count` 条记录，且无尾部多余字节；任意一条记录类型未知、长度不足或格式错误时，整批丢弃。

---

### 5.16 用户动作与事件映射

| 用户在设备上的动作 | 固件应发送 | App 当前行为 |
|------------------|------------|--------------|
| 设备上线（BLE Notify 建立后，固件发 Wake Notify） | `DeviceWake(0x30)`，payload 带 `BatteryLevel(1B)` | 更新电量，发送 Time，并按需同步数据 |
| 用户手动刷新 | `RequestRefresh(0x20)` | 触发一次数据同步；**联调期用 60 秒合并窗去抖**（固件把 0x20 当 ~2s 心跳狂发，App 把整轮 sync 合并为 ≤1 次/分，窗内重复被合并并记录日志）；**不**与 `DeviceWake(0x30)` 的 10 秒节流共用（见 §8.5）。固件停止心跳化后此窗可回调更短、用户按键即时触发 |
| 在任务列表中进入任务详情 | `EnterTaskIn(0x10)`，payload 带 TaskId 和时间戳 | 回发 `TaskInPage(0x11)`，并启动专注会话 |
| 在任务详情页完成任务 | `CompleteTask(0x11)`，payload 带 TaskId 和时间戳 | App 标记任务完成，结束对应专注会话 |
| 在任务详情页跳过任务 | `SkipTask(0x12)`，payload 带 TaskId 和时间戳 | 结束对应专注会话，不标记完成 |
| 普通旋钮确认但不进入任务详情 | `WheelSelect(0x14)` | 只记录/调试，不回发页面数据 |
| 查看日程详情 | `ViewEventDetail(0x15)` | 当前不回发详情 |

---

## 6. 页面数据结构

> **v2.5.0 重写**：设备 UI 是「常驻框架 + 可换数据面板」，不再是「4 页各说一句」。旧 §6.1–6.4（每页一句宠物文案）已废弃，论证见 §6.5。

### 6.1 常驻框架

设备主界面是一个**常驻框架**，不随内容翻页：

- **顶栏**：天气（来自 `0x04 Weather`）+ 日期（DayPack `Year/Month/Day`）
- **左侧**：宠物形象 + **常驻对话气泡**（始终在场，三态一致）

**数据来源：** DayPack.`PetDialogue`（= App `currentPetDialogue`，阶段感知；早上即早安、傍晚即结算语，见 §6.5）。

---

### 6.2 概览面板（默认）

框架右侧的默认数据面板：

- 今日**事件卡**（时间 + 标题 + 描述）
- **置顶任务清单** + 完成状态（4寸 ≤3 条，7.3寸 ≤5 条）
- **进度**（已完成 / 总数）

**数据来源：** DayPack.`Events[]` / `TopTasks[]` / `SettlementData`（数值字段）。

⚠️ 「进度条 vs 任务清单」二选一或并列的具体布局，由固件 / 产品在重写时定（App 两者都发）。

---

### 6.3 专注详情面板

用户在设备上选中任务进入专注时显示：

- 任务标题 + 描述 + Tips（鼓励）
- 能量瓶

**数据来源：** `0x11 TaskInPage`（由设备 `0x10 EnterTaskIn` 触发）+ `0x14 FocusStatus`（专注状态与能量瓶实时推送）。**不在 DayPack 内。**

---

### 6.5 设计论证：显示模型对齐到「1 宠物气泡 + 可换数据面板」（v2.5.0 已采纳）

> 状态：**已采纳（产品确认）**。自 v2.5.0 起 §4.7 / §6 已按本节重写。本节保留为设计论证与决策记录；仍以 ⚠️ 标注需固件在重写时确认的实现细节。

**背景 / 问题**

现行 §6 把硬件建模成「4 个独立页面，每页各有一句宠物文案」：页面 1 `morningGreeting`、页面 2 `companionPhrase`、页面 4 `settlementData.summaryMessage`/`encouragementMessage`——共约 4 处宠物口吻文本，分散在不同页面。

但产品最新实机 UI（设计稿三态）并非「多页各说一句」，而是一个**常驻框架 + 可换右侧面板**：

- 顶栏：天气 + 日期（常驻）
- 左侧：宠物形象 + **一个常驻对话气泡**（三态中文案一致，是宠物当前的「一句话」）
- 右侧：随场景切换的**数据面板**：
  - 态 A（日程）：今日事件列表（时间 + 标题 + 描述）+ 进度条
  - 态 B（日程 + 任务）：事件 + 任务清单（bullet）
  - 态 C（专注）：当前任务详情（标题 + Tips）+ 能量瓶

即：**宠物口吻文本只有一处（气泡）**，其余皆为结构化事实数据。现行协议里的 `morningGreeting` / `dailySummary` / `companionPhrase` / settlement 双消息，属于旧「多页多句」模型的冗余。

**关键论证：App 那句本就按时段「变脸」，硬件直接同步即可，无需多句**

App 首页宠物头顶只有**一个**对话槽 `currentPetDialogue`，由阶段状态机（`AppState+Companion.resolveCompanionPhase`）按上下文自动选型：`.morningPrep → .morningGreeting`（早安）、`.inTask → .taskEncouragement`、`.daySettled → .settlementSummary`（结算语）、`.idle → .smartReminder`（陪伴）。也就是说——**「早安 / 陪伴 / 结算」这些口吻 App 本来就都有，只是同一个槽在不同时段说不同的话**，不是三块常驻文本。

而旧 DayPack 的 `morningGreeting / companionPhrase / settlement 双消息`，是 `DayPackGenerator` **另外单独生成**的（仅供硬件用，App 界面从不显示），与 App 那句**各算各的、内容可能不一致**。结论：硬件气泡**不该自己再造一套**，直接同步 App 的 `currentPetDialogue` 即可——早上同步时它自然是早安、傍晚同步时它自然是结算语。这既消除了重复 LLM 生成，又保证「宠物在 App 和硬件上是同一个、说同样的话」。

**提案要点**

1. **宠物文本收敛为单字段 `PetDialogue`**（气泡），数据源 = App 首页 `currentPetDialogue`（与 App 宠物头顶同一句，真正同源、人格一致）。废弃 `MorningGreeting` / `CompanionPhrase` 作为独立宠物文案。
2. **右侧面板改由结构化字段驱动**：
   - 事件：现协议只有 `FirstItem`（单行）+ `CurrentScheduleSummary`（计数），**不足以渲染设计稿的事件卡（含描述）**。提案新增 `Events[]`（每条：time + title + description）。App 侧 `CalendarEvent` 已含 description，可直接喂。
   - 任务清单：复用现有 `TopTasks[]`。
   - 进度条：复用 `SettlementData.TasksCompleted/TasksTotal`。
   - 专注详情（态 C）：仍走 `TaskInPage(0x11)`，不变。
   - 能量瓶（态 C）：复用 `SettlementData.TotalEnergyBottles`。
3. **面板态由谁决定**：~~建议 App 置一个 `PanelMode` 字节，固件据此渲染~~ ← **已拍板（v2.5.15）：不新增 `PanelMode` 字节，面板态由固件本地判定**，规则见 **§6.7**。原提案「App 是显示决策方」的语义修正为：App 决定**内容**（数据与文案），固件决定**时机与状态**（本地 RTC + 已收数据 + 按键）——BLE 断连是常态，App 下发的模式字节会在离线期间冻结失真；同类产品（Pebble / InfiniTime）屏幕状态均为设备本地状态机。

**UI 元素 → 数据字段 映射（提案）**

| 设计稿元素 | 数据来源（提案） | 现状 |
|---|---|---|
| 顶栏 天气/日期 | Weather + Year/Month/Day | 已有 |
| 宠物气泡（三态一致） | **PetDialogue（= App currentPetDialogue）** | 旧：morningGreeting / companionPhrase 分散 |
| 一天总结段落（框②） | **DaySummary（v2.5.7 新增，面板文本，≤180B）** | 旧：dailySummary 曾删，现作面板文本复活 |
| 下一项「First up」（框③） | **FirstUp（v2.5.8 新增，App 算，≤60B）** | 旧：仅 firstItem 单行；现为 App 算好的「下一个事件/任务」标签 |
| 事件卡（时间 + 标题 + 描述） | **Events[]（新增 description）** | 缺（仅 firstItem / scheduleSummary） |
| 任务清单 | TopTasks[] | 已有 |
| 进度条（如 50%） | SettlementData.completed/total | 已有 |
| 专注任务详情 | TaskInPage(0x11) | 已有 |
| 能量瓶 | SettlementData.totalEnergyBottles | 已有 |

**已定决策（v2.5.0）**

- **气泡语气**：直接用 App 的 `currentPetDialogue`（阶段感知），接受其按时段变脸的语气。不在硬件侧另取一句。
- **面板态**：DayPack 只承载「概览」数据（PetDialogue + Events[] + TopTasks[] + 进度/能量来自 SettlementData）；**不引入 `PanelMode` 字节**，设备按现有数据渲染。专注态（态 C）仍由 `0x10 EnterTaskIn → 0x11 TaskInPage` + `0x14 FocusStatus` 独立驱动，不在 DayPack 内。⚠️ 设备端「进度条 vs 任务清单」二选一的布局规则需固件/产品在重写时定，App 两者都发。
- **事件描述**：`Events[]` 每条 `Time(≤8B) / Title(≤40B) / Description(≤120B)`，沿用 §4.7 流式变长 + 按 UTF-8 字节边界截断。
- **结算双消息**：删除 `SummaryMessage / EncouragementMessage`——宠物口吻统一由 `PetDialogue` 承载；`SettlementData` 仅保留数值字段（完成/总数、积分、专注指标、能量瓶），用于进度条与能量瓶展示。
- **进度/能量**：复用 `SettlementData` 数值，不单列新字段。
- **一天总结（框②，v2.5.7 补充）**：在「宠物气泡单句」之外，**面板上保留一段独立的「一天总结」文本** `DaySummary`（≤180B，§4.7 末尾追加）。这**不是回退** v2.5.0 的单气泡决策——宠物**口吻**仍只有 `PetDialogue` 一句；`DaySummary` 是**非宠物口吻的概览段落**（情绪向、只谈日程、附一条实用建议），由 `DayPackGenerator` 喂今日事件明细生成。分工：「气泡 = 宠物说的一句话」「DaySummary = 面板上的一天概览」，两者不重复。当年删 `dailySummary` 删的是「另造一套宠物口吻」的冗余，本次复活的是「面板概览段落」，定位不同。

**迁移 / 兼容**

- 这是**破坏性协议变更** → 采纳后协议版本号 +1，§4.7 / §6 整体改写，App `DayPack` 结构体同步精简。
- 时机较好：固件 §8.7 正在修 DayPack 解析（当前把字符串当定长数值、整体错位）；趁这次解析重写**一并对齐新布局**，避免改两次。
- v2.5.0：App 侧 `DayPack` 结构体与 `BLEDataEncoder` 已按新 §4.7 落地；**固件需对照新 §4.7 实现解析后双方才能联通**（在此之前硬件 DayPack 显示本就不工作，无回归）。

---

### 6.6 字体与排版：字段 → 字体映射（固件渲染职责，wire 不变）

硬件内置**两套字库**，按字段的**语义角色**渲染——**字体不走 wire、App 不下发任何字体选择字节**（字段身份本身即字体选择器，沿用 §6.5「App 传内容/语义、固件渲染」原则）：

| 字体 | 用途 | 对应字段 |
|------|------|----------|
| **Lugrasimo**（手写 / 装饰体） | **宠物口吻** | `PetDialogue`（页面一框①气泡）—— **仅此一处** |
| **Calibri**（无衬线 / 数据体） | 其余**所有**中性·数据文本 | 顶栏 `Weather`（温度/天气/日期）、进度/结算、`Events[]`（事件卡标题+描述）、`DaySummary`、`FirstUp`、`TaskInPage`、`SmartReminder`、屏保 `Screensaver` 的 Quote/Author 等 |

**固件实现要点：**

1. **按字段映射字体**：渲染 `PetDialogue` 用 Lugrasimo，渲染任何其它文本字段用 Calibri。无需 App 提示——固件已知道「这是哪个字段」。
2. **字形回退（兜底安全网，非常态）**：自 BLE v2.5.14 起，App 已在编码边界把**所有**出站文本净化为纯可打印 ASCII（`0x20`–`0x7E`，见 §3.5）——`PetDialogue` 里原先偶发的弯引号 `’ “ ”` / 长破折号 `—` / emoji **不再到达固件**（已在 App 侧转为直引号 `'`、`-`，emoji 丢弃）。因此 **Lugrasimo 只需覆盖可打印 ASCII（`0x20`–`0x7E`）字形即可**；万一某个 ASCII 字形 Lugrasimo 仍缺失，**回退 Calibri** 渲染该字符（标准 glyph fallback）——此回退现在仅是兜底安全网，正常不会触发。（背景：此前固件对弯引号/emoji 未优雅回退而渲染成豆腐块 `□`，v2.5.14 从源头消除该输入。）
3. **不要逐串传字体**：字库已烧进固件，逐串传字体既费带宽又费内存；嵌入式 e-ink 的通行做法是「角色 → 字体」映射，而非每串携带字体。

**何时才需要 App 传字体**：仅当字体变为**动态**——用户可在 App 内选字体 / 逐条消息字体不同 / 同一字段运行时换字体。当前是**固定设计映射**，故**不引入字体字节**（YAGNI，同 §6.5/§6.7 不引入 PanelMode 的同类取舍）。

### 6.7 面板态判定：固件本地状态机（v2.5.15 拍板，wire 不变）

§6.5 提案要点第 3 条的开放问题在此关闭：**不新增 `PanelMode` 字节，态 A / B / C 由固件本地判定**。职责分界与 §4.6 时间同步一脉相承——App 负责**内容**（把数据算好发全：DayPack 的 `Events[]` / `TopTasks[]` / `SettlementData` / `FirstUp` / `PetDialogue`）与**校时**（`0x05`）；固件负责**时机与状态**（用本地 RTC + 已收数据 + 用户按键决定当下渲染哪个态）。

**为什么不是 App 下发模式字节**：App 同步是节流的（§8.5，白天约 1 小时一轮），且 BLE 断连是常态——App 置的模式字节会在离线期间冻结失真（例：白天最后一轮置「日程态」，晚间手机不在则永远进不了结算展示）。同类产品分工一致：Pebble Timeline 手机只同步结构化 pin、手表本地按自身时钟渲染「过去/现在/将来」；BLE 标准 CTS 手机仅作时间服务器、设备走本地 RTC；InfiniTime 各屏是固件本地事件驱动状态机，伴侣 App 只做校时/通知/DFU。

**判定规则（按优先级，自上而下第一条命中即渲染）：**

| 优先级 | 条件（固件本地判定） | 渲染 |
|---|---|---|
| 1 | 专注会话激活中（收到 `TaskInPage(0x11)` 后、会话尚未结束；结束/中断判定见 §9） | 态 C（专注详情 + 能量瓶） |
| 2 | 非专注，且 `TopTasks[]` 存在未完成任务（`IsCompleted=0x00`） | 态 B（事件 + 任务清单） |
| 3 | 非专注、无未完成任务，且 `Events[]` 非空 | 态 A（事件列表 + 进度条） |
| 4 | 以上皆不满足（无事件且无未完成任务） | 固件空态兜底（宠物 + `PetDialogue` + `DaySummary`；具体版式随实机 UI 定稿） |

**补充约定：**

- 面板**内部**的时间推进（当前/下一事件高亮、`Events[].Time` 与本地时钟比较）同样固件本地做（见 §4.4 / §4.6）。
- 仍由 App 下发的是**设置类**状态，不属于面板态：`DeviceMode(0x12)`、`Screensaver(0x16)`、`SceneUnlock(0x17)`。
- 数据变化（用户增删改任务/日程、专注结束结算）经既有同步通道到达（§8.5 节流 / `0x20` 请求刷新 / 指纹变化触发）后，固件按上表**重判**；App 不发送任何面板态字节。
- ⚠️ 待与固件定稿的边界值：晚间倾向结算展示的起始时段；「进行中事件」的持续窗口（wire 无事件结束时间，建议按「下一事件开始前」或固定窗口处理）。定稿后补入本节。

---

## 7. 示例数据

### 7.1 DayPack 最小测试向量（Hex）

> ⚠️ **下方 hex 向量是 pre-v2.5.0 旧布局，已废弃，切勿照其实现解析（v2.5.9）。** 它含 `MorningGreeting / DailySummary / FirstItem / CurrentScheduleSummary / CompanionPhrase` 及结算双消息——这些字段 v2.5.0 已删除，与现行 §4.7 完全不符。手工维护逐字节向量会随协议演进错位、反误导固件，故不再在此给出新向量，改为下面的**当前字段顺序** + 指向 App 侧锁步维护的**权威往返自检**。
>
> **当前 DayPack(0x10) payload 字段顺序**（详见 §4.7；变长字符串 = 1 字节长度 + UTF-8 内容，长度为 0 的空串也占 1 字节、必须照样消费再前进）：
> `Year(1) Month(1) Day(1) DeviceMode(1) FocusChallengeEnabled(1) PetDialogue(1+N) EventCount(1) Events[]{Time(1+N) Title(1+N) Description(1+N)}×N TaskCount(1) TopTasks[]{TaskId(1+N) Title(1+N) IsCompleted(1) Priority(1)}×N SettlementData(10B 定长) DaySummary(1+N) FirstUp(1+N，最后一个字段)`。读完 `FirstUp`，解析指针应恰好停在 payload 末尾。
>
> **权威自检（推荐固件对照）**：App 侧 `BLEProtocolSimulationSupport.swift::parseDayPack()` 按上序逐字段读回并 `requireEnd()`（任何尾部多余字节即报错），与 `BLEDataEncoder.encodeDayPack` 在 `BLEProtocolSimulationTests` 做往返断言；编解码**锁步维护**，是当前布局的权威字节级参考。固件实现解析器后，可请 App 侧据此导出一条与现行布局一致的具体 hex 向量。

以下测试向量用于验证字段顺序和长度解析，可作为固件解析器的第一条样例。它不是产品真实文案，只覆盖最小字段。左侧 `@N` 为该字段在 **payload 内的起始字节偏移**（十进制），供固件逐字段对位——注意偏移随变长字符串累积，**不是固定值**。

```
Command: 0x10 (DayPack)

Full Packet:
10 00 3A                              // Type=0x10, Length=58 (payload 共 58 字节)

Payload (58 bytes):
@0   1A 05 08                         // Date: 2026-05-08 (year=0x1A=26→2026, month=5, day=8)
@3   00                               // DeviceMode: Interactive
@4   00                               // FocusChallengeEnabled: false
@5   02 48 69                         // MorningGreeting: len=2 "Hi"
@8   08 4F 6E 65 20 74 61 73 6B       // DailySummary: len=8 "One task"
@17  05 46 6F 63 75 73                // FirstItem: len=5 "Focus"
@23  00                               // ★ CurrentScheduleSummary: len=0 → 空串，仅此 1 字节、无内容
@24  06 53 74 61 72 74 2E             // CompanionPhrase: len=6 "Start."
@31  00                               // ★ TaskCount: 0 → 其后无任何 TopTask 子结构，直接进入 Settlement
// Page 4: Settlement (@32 起)
@32  00                               // TasksCompleted: 0
@33  01                               // TasksTotal: 1
@34  00 00                            // PointsEarned: 0 (u16 BE)
@36  00 00                            // TotalFocusMinutes: 0 (u16 BE)
@38  00                               // FocusSessionCount: 0
@39  00 00                            // LongestFocusMinutes: 0 (u16 BE)
@41  00                               // InterruptionCount: 0
@42  05 44 6F 6E 65 2E                // SummaryMessage: len=5 "Done."
@48  09 54 6F 6D 6F 72 72 6F 77 2E    // EncouragementMessage: len=9 "Tomorrow." (@48..@57 = payload 末尾)
```

**两个 `★` 是固件最容易错位的点**：`@23` 的 `00` 是空字符串（长度 0、没有内容字节），`@31` 的 `00` 是零任务（TaskCount=0、其后没有 TopTask）。固件必须照样消费这 1 个字节再前进；少读这一字节就会从此处整体错位，正是 §8.7「问题 1」把字符串当数值读的现象。

**自检通过标准**：解析后应得到 `MorningGreeting="Hi"`、`DailySummary="One task"`、`FirstItem="Focus"`、`CurrentScheduleSummary=""`、`CompanionPhrase="Start."`、`TaskCount=0`、`SummaryMessage="Done."`、`EncouragementMessage="Tomorrow."`，且解析指针**恰好停在第 58 字节**（无剩余字节、无越界读取）。

如果该 payload 通过分包发送，单包 CRC16-CCITT-FALSE 为 `0x0F50`。

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
| 意外断开 | 若已启用则自动重连：采用 CoreBluetooth pending connection（`retrievePeripherals` 取回已知设备 + 不超时 connect，不再循环扫描），等待设备回到范围后自动重连 |

**主动断开不重连**：App 主动断开（sync 收尾、用户点击断开、后台任务到期、连接超时取消）**不会**触发自动重连，会等待下一个同步窗口或用户操作。固件无需为此场景做特殊处理，正常保持广播即可——下一个同步窗口 App 会重新发起连接。

### 8.2 数据校验

| 校验项 | 规则 |
|------------------------|-------------------------------------------|
| 字符串长度 | 按 UTF-8 字节数截断至最大长度，不切断多字节字符 |
| 整数溢出 | 限制在有效范围内；负数按 0 处理 |
| 简单包长度 | 必须正好等于头部长度 + Payload 长度，不允许尾部多余字节 |
| SecureEnvelope 长度 | 必须正好等于固定头 + payloadLen + 32B signature，不允许尾部多余字节 |
| EventLogBatch | 必须整批完整解析，否则整批丢弃 |
| 无效事件类型 | 忽略未知事件类型 |
| 格式错误的数据包 | 丢弃并记录错误 |

### 8.3 固件侧建议处理

| 场景 | 固件建议行为 |
|------|--------------|
| 收到未知 App→Device type | 忽略该包，不刷新屏幕 |
| 简单包长度不等于 `3 + Length` | 丢弃该包 |
| 分包 CRC 错 | 丢弃该分包；如果无法补齐整条消息，超时后丢弃整条消息 |
| 分包缺包或超时 | 丢弃该 MessageId 下所有已缓存分包 |
| 分包总数超过 255 | 丢弃 |
| 明文联调包里收到 `SecureData(0x7E)` | 忽略，除非本轮已启用安全模式 |
| 安全模式下收到非 `0x7E` / `0x7F` 业务包 | 忽略或断开连接；正式策略以后续安全联调为准 |

### 8.4 重试策略

| 操作 | 最大重试次数 | 退避间隔 |
|------------------------|-------------|------------------------|
| Scan                   | 3           | 2s, 4s, 8s             |
| Connect                | 3           | 1s, 2s, 4s             |
| Write                  | 2           | 500ms, 1s              |
| CustomAvatarFrame(0x15) | 不设固定上限（退避降频，见 §4.12）| 前 5 轮 sync 每轮，之后每 20 轮一次；永不永久放弃 |

> `0x15` 不走「固定次数 + 时间退避」模型，而是「按 sync 轮次降频、永不放弃」——详见 §4.12「App 侧重发策略」。

### 8.5 App 侧写入限流

App 内置写入速率限制，固件联调时需注意：

| 限制项 | 规则 |
|------------------------|-------------------------------------------|
| 最大写入速率 | 20 次/秒，超出时 App 自动排队等待 |
| DeviceWake sync 触发最小间隔 | 10 秒，**仅** DeviceWake(`0x30`) 触发的整轮 sync 适用。10 秒内重复 DeviceWake 时，App 仍会处理电量、发送 Time、记录硬件唤醒，但整轮 sync 会被节流并记录日志，以避免「连上 → wake → sync → 断开 → 重连 → wake」的连接风暴 |
| RequestRefresh sync 触发最小间隔（合并窗） | **60 秒（联调期）**，**仅** RequestRefresh(`0x20`) 触发的整轮 sync 适用。使用**独立**闸，不消耗 DeviceWake 的 10 秒配额、也不会被频繁 DeviceWake 饿死。**联调期固件把 0x20 当 ~2s 心跳狂发**，60 秒合并窗把 30 次/分的背靠背 sync 去抖为 ≤1 次/分（窗内重复被合并并记录日志）；固件停止心跳化后可回调更短值、用户按键即时触发。（历史：曾短暂**硬抑制** 0x20，连带停掉用户物理刷新；v2.5.14 改为去抖合并、恢复用户刷新。）|

**调试建议**：若发现 App 长时间无响应或未按预期刷新，可检查是否触发了限流——`0x20` 触发的整轮 sync 在 **60 秒合并窗**内被去抖（联调期，防固件把 0x20 当心跳刷屏）、`0x30` 在 10 秒内重复触发整轮 sync 会被忽略（两者互不占用配额），或写入频率超过 20 次/秒被排队。

**帧可见性（联调）**：DEBUG 包与 TestFlight 包可用 Console.app 过滤 `subsystem:com.kirole.app category:BLE` 查看 App 收发帧摘要——TX 记录 `type/len`、RX 记录 `len/firstByte`；正式 App Store 包关闭，且不记录完整 payload。

**同步回路：Time(0x05)→RequestRefresh(0x20) 反射与 DayPack 双发（2026-07-03 联调）**

联调实测：固件每收到 `Time(0x05)` 即回一个 `RequestRefresh(0x20)`（固件日志 `RTC synced → Triggering RequestRefresh`）。而 Time 是 App **每轮 sync 的第一帧**——"收到同步的开头就请求新同步"构成自激回路：该 0x20 到达时本轮 sync 尚在途，App 会在收尾后补跑一轮 force sync；若两轮之间恰有内容变化（典型：LLM 对话文本在 ~3 秒内生成完成），第二轮真发 DayPack——硬件 3 秒内收到 MsgID 连号、除 PetDialogue 外完全相同的两个 DayPack，背靠背双刷屏。首次连接与任务/日程变更后最易复现（这两种场景对话必然重新生成）；对话缓存命中时两轮内容一致、第二轮不发 DayPack，现象即"消失"。

- **App 侧已修（build 589）**：sync 组包前等待在途的对话生成完成（首轮即携带最终文本）；此后反射补跑轮因指纹无变化**不再携带 DayPack**，退化为 Time/PetStatus 小帧，不触发刷屏。
- **固件侧建议**：
  1. 收到 `Time(0x05)` **不要**触发 `RequestRefresh(0x20)`。0x20 只保留两种意图：开机/唤醒后久无数据、用户物理按键刷新。App 每轮 sync 都会主动推送全量数据，无需设备回请。
  2. E-ink 渲染进行中（7.3 寸全刷 ~12s）收到新 DayPack 时，**合并到下一次刷新**（只保留最新一包），不要排队逐包刷屏。

### 8.6 设备信任模型（TOFU）

App 采用 **首次连接即信任（Trust On First Use）** 策略：

- 首次连接成功的设备 UUID 会被永久记录为"受信任设备"
- 后续扫描时，若已有受信任设备，**其他未知设备会被直接过滤**，不会出现在扫描结果中
- 如需连接新的测试设备，须先在 App 设置中清除已记录的设备信任记录

**联调注意**：更换测试硬件时，如果 App 扫描不到新设备，通常是此机制导致，清除信任记录后重新扫描即可。

### 8.7 联调实测：固件实现偏差（2026-05-29 `ble_log`）

本节记录一次真机联调日志（`ble_log`）中观察到的**固件实现与本规格不一致**的问题；以下是固件需对照修正的点。（App 侧节流策略已于 v2.4.1 调整，以 §8.5 最新版本为准。）

**问题 1：DayPack(0x10) payload 字段错位（最严重）**

固件日志打印 `Schedules: 18287, Tasks: 28516`，但 §4.7 的 DayPack 在 Header(5B) 之后是**变长字符串**（MorningGreeting…），不存在「Schedules / Tasks 计数」这类定长数值字段。

定位证据：`18287 = 0x476F = "Go"`、`28516 = 0x6F64 = "od"`，正是 MorningGreeting = `"Good morning…"` 的 UTF-8 字节被当成了两个 16 位整数。说明固件解析器停留在某个**旧版 DayPack 布局**，把字符串区当成了定长字段，从此处开始整体错位。

→ 固件须严格按 §4.7 + §3.5 解析 Header(5B) 之后的字段：**先读 1 字节长度、再读对应字节数**的变长字符串，依次 MorningGreeting / DailySummary / FirstItem / CurrentScheduleSummary / CompanionPhrase，然后才是 TaskCount + TopTasks[] + SettlementData。请用 §7.1 的最小测试向量自检解析器。

附 `Date` 异常（日志 `6661-29-00`，其中 day=29 正确）：按 §4.7，Header 为 `Year(=年-2000) / Month / Day` 各 1 字节单字节，请确认固件未把年份当成多字节、且做了 `+2000`。

**问题 2：入站命令 `0x01` / `0x20` 报 `Unknown cmd type`**

固件对 App 发来的 `0x01`(PetStatus) 与 `0x20`(EventLogRequest) 打印 `Unknown cmd type`。根因见 §2.4：这些字节在 Device→App 方向另有含义（`0x01`=EncoderRotateUp、`0x20`=RequestRefresh），固件用了「发送方向」的定义去解释「收到」的字节。

→ 固件分发必须**按方向**：从 `FFE1`(Write) 收到的字节查 §4「App→Device 命令表」，自己经 `FFE2`(Notify) 发出的字节查 §5「Device→App 事件表」，两张表不可共用。需补齐 §4 中 App→Device 命令的接收实现（至少 PetStatus `0x01`、EventLogRequest `0x20`）。

**问题 3：`0xAA` 开发显示命令报 `Unknown cmd type`**

固件若仍收到 `AA 01 01 …` / `AA 01 02 …` 打印 Unknown：这些旧 `0xAA` 开发显示命令**已于 v2.5.10（屏保→`0x16`）/ v2.5.11（场景解锁→`0x17`）全部升级为业务帧**，App 出站不再产生任何 `0xAA`。若仍收到，说明是过时 App，固件可安全忽略并把它从错误日志降级为 debug。见 §4.15 / §4.16。

> **帧层经本次联调验证正常，无需改动**：App 的 Time(`05 00 06 1A 05 1D 09 2A 28`) 被固件正确解析为 `2026-05-29 09:42:40`；设备的 DeviceWake(`30 01 64`) 被 App 正确解析为电量 100%。问题集中在 DayPack payload 结构与命令字节的方向分发，不在分包 / CRC / 长度宽度。

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
- 离线回放事件只保证任务完成状态能补记；离线期间的专注时间不保证完整计算，因为 App 没有当时的手机解锁数据。
- 回放补记任务完成时只应用状态变更（任务状态、宠物积分、持久化、外部同步），不触发实时反馈（声音/震动/完成俳句）——这些只属于实时用户操作（v2.5.2）。

---

## 10. Spectra 6 像素数据格式

> **注意：** 屏幕硬件规格（分辨率、色彩技术）的权威来源为 `硬件需求文档-Hardware-Requirements-Document.md` Section 4。本节仅描述像素数据在 BLE 传输中的编码格式。

### 10.1 概述

E-ink 显示屏使用 E Ink Spectra 6 技术，支持 6 种颜色。像素数据采用 4bpp（每像素 4 位）格式编码，每字节打包 2 个像素。

本节仅保留像素编码定义。当前 iOS App 没有正式图片帧业务命令，第一轮 BLE 联调不要求固件实现图片帧接收。

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
| 7.3 寸| **1600 x 1200** | 1,920,000 | **960,000 bytes (937.5 KB)** |

> ⚠️ **2026-06-25 更正**：7.3 寸面板分辨率经硬件确认为 **1600×1200（4:3）**，非旧版 800×480；缓冲区随之 192,000 → 960,000 bytes。4 寸（400×600）未定，不动。权威来源仍为硬件需求文档 §4。

公式：`bufferSize = width * height / 2`

---

## 附录 A：Swift 类型参考

### A.1 BLEDataType Enum

定义位置：`KirolePackage/Sources/KiroleFeature/Core/BLE/BLEProtocol.swift`（单一真相源）

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
    case focusStatus = 0x14   // App→Device: 推送当前专注状态和能量瓶子数
    case customAvatarFrame = 0x15  // App→Device: 自定义伴侣像素帧（⚠️ 待对齐，见 §4.12）
    case screensaver = 0x16        // App→Device: 屏保金句/明信片业务帧（替代旧 0xAA 01 02，见 §4.15）
    case sceneUnlock = 0x17        // App→Device: 场景解锁业务帧（替代旧 0xAA 01 01，见 §4.16）
    case eventLogRequest = 0x20
    case eventLogBatch = 0x21
    case secureData = 0x7E
    case securityHandshake = 0x7F
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
| 硬件需求文档-Hardware-Requirements-Document.md | v0.4 | 硬件电气需求（SoC、显示、电源、电池） |
| 固件功能规格文档.md | v1.4.1 | 固件功能规格（页面设计、交互流程、伴侣显示系统） |

---

## 联系方式

如有协议问题或需要澄清，请联系 Kirole 开发团队。

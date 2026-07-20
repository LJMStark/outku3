# Kirole BLE 通信协议规格文档

**版本:** v2.5.31
**更新日期:** 2026-07-20
**状态:** DayPack 显示模型重写（1 气泡 + 数据面板）。**破坏性变更：固件需按新 §4.7 / §6 重写 DayPack 解析（与 §8.7 修复一并做）。** FocusStatus(`0x14`) 新增 `SegmentMinutes` 字段（追加在 TaskTitle 后，前向兼容）；`ElapsedTime` 保持「本会话累计分钟」语义不变（v2.5.5）。`Mood`/`PetMoodByte` 明确为**前向兼容通道**：App 持续下发真实心情值，固件当前阶段可忽略、不据此展示或换图（v2.5.6，§4.2 / §4.10）。DayPack 末尾追加 `DaySummary`（框②「一天总结」：情绪向·只谈日程·≤180B），作为面板文本字段复活、与单句 `PetDialogue` 互补，不回退单气泡决策（v2.5.7，§4.7 / §6.5）。DayPack 再追加 `FirstUp`（框③「下一项」：下一个未来事件「HH:mm 标题」/ 无则置顶任务 / ≤60B，App 算好下发，现为 DayPack 最后一个字段）（v2.5.8，§4.7）。Weather(`0x04`) 在 Condition 后追加 `HighTemp`/`LowTemp`（顶栏高/低温，各 1B 有符号 int8）（v2.5.9，§4.5）。屏保金句/明信片（`Screensaver`）从旧 `0xAA 01 02` 开发命令升级为 `0x16` 业务帧（经 SecureEnvelope，**secure 模式可发**；旧开发命令在配置 `BLE_SHARED_SECRET` 后被禁用、屏保静默发不出去）（v2.5.10，§4.15）。场景解锁（`SceneUnlock`）同样从旧 `0xAA 01 01` 开发命令升级为 `0x17` 业务帧（secure 可发）；至此两条 `0xAA` 开发显示命令全部退役（v2.5.11，§4.16 / §4.14）。§4.15 澄清屏保帧传输：Quote/Author 较长或 secure 封装后整体可能超过协商 MTU 而**分包**（按 §3.2 通用分包重组），并非恒为单包；固件须按分包处理（v2.5.12）。新增 §6.6 字体与排版：两套字库（Lugrasimo=宠物气泡 / Calibri=其余所有文本）按**字段语义角色**渲染、字体不走 wire、App 不传字体字节、固件按字段映射 + 字形回退（v2.5.13，纯文档）。§3.5 补记 App 出站文本 **ASCII 净化保证**：所有字符串字段在编码边界被净化为仅含可打印 ASCII（`0x20`–`0x7E`），非 ASCII（LLM 弯引号/破折号/省略号、用户/日历带入的 emoji/重音/CJK 等）转写为 ASCII 近似或丢弃——固件收到的文本字段恒为 ASCII，§6.6 的 Lugrasimo 缺字回退随之从常态降级为兜底（v2.5.14，§3.5/§6.6）。同记 `RequestRefresh(0x20)` 联调期**去抖合并**：固件把 0x20 当 ~2s 心跳，App 用 60s 合并窗把整轮 sync 去抖为 ≤1 次/分（v2.5.14，§8.5）。两者均为 App 侧行为，wire 格式不变。面板态判定拍板：**不新增 `PanelMode` 字节**，态 A/B/C 由固件本地状态机判定（本地 RTC + 已收数据 + 按键），App 只负责内容与校时——与 Pebble Timeline / BLE CTS / InfiniTime 同类分工一致；新增 §6.7 判定规则，§6.5 开放问题关闭（v2.5.15，纯文档、wire 不变）。§8.5 补记 `Time(0x05)`→`RequestRefresh(0x20)` **反射回路与 DayPack 双发**（2026-07-03 联调：MsgID 连号、~3 秒差、除 PetDialogue 外相同的两个 DayPack）——App 侧已修（组包前等待在途对话生成完成，首轮即最终文本；反射补跑轮内容无变化时不再携带 DayPack）；**固件侧建议**：收到 Time 帧不应触发 0x20（0x20 仅用于开机后久无数据与用户物理按键），渲染进行中收到新 DayPack 应合并到下一次刷新。§4.7 补记 TopTasks **实现对齐**：规格上限一直是 4寸≤3 / 7.3寸≤5，App 端此前固定按 4 寸档发 ≤3 条，build 589 起按 Settings 配置的屏型发满上限、同优先级截取顺序确定化（priority→dueDate→id）。均为 App 行为 / 文档记录，wire 不变（v2.5.16，§8.5/§4.7）。§4.5 补记 **Weather(0x04) 自 build 593 起首次真实发送**（此前挂在死路径上从未发出、硬件顶栏天气从未更新）：每轮 sync 无条件发、仅天气变化时放行小帧轮（不触发 DayPack 全刷）、无真实数据不发；§8.7 新增**问题 4**：EnterTaskIn(0x10) payload 未按 §5.3（实测 8 字节 idx+timestamp、无 UUID → App 解析空 taskId、不回 0x11、回 DeviceMode 解卡但设备未退页），附正确字节示例与 App 侧防御说明；另记专注显示推送合流（0x14 idle 立即 / 0x17 仅新解锁 / 同内容 0x14 2 秒去重）。wire 均不变（v2.5.17，§4.5/§8.7）。新增 OTAReboot(`0x18`)/OTAResult(`0x18`)——App→Device 触发固件升级重启（零 payload）、Device→App 应答（1B 状态码），沿用既有方向双义规则（同 `0x10`~`0x17`/`0x20`）。固件验证升级包合法后先发应答、**不等 App 确认**即直接重启进入升级（约 20 秒，期间 BLE 关闭）；App 侧因此把"未收到应答前先断连"与"收到 `0x00`"同等对待（均判定为大概率成功）：连接仍存活但 5 秒无应答则重发（至多 3 次，~15 秒后判失败）；一旦断连则停止重发、转入"等待设备回来"态，抑制该窗口内的连接错误提示，靠 `DeviceWake(0x30)` 确认成功，~90 秒兜底超时后降级为失败提示。安全模式（`BLE_SHARED_SECRET` 已配置）下 `0x18` 与其他业务帧一样须走 `SecureEnvelope`（`0x7E`）封装；当前 dev 与现有 TestFlight 包均未启用安全模式，本轮按明文联调，正式启用前需与固件再次对齐（v2.5.18，§4.17/§5.17/§2.4/§4.1/§5.2）。DeviceWake(`0x30`) 在 BatteryLevel 后**追加固件版本 3 字节** `FwMajor/FwMinor/FwPatch`（设备端 Major.Minor.Patch 三段式，各 1B，v2.5.19+ 固件必填，App 兼容旧 1B/空 payload）——关闭 §4.17「升级成功与回滚不可分」已知边界：App 进入升级等待态前快照当前版本、DeviceWake 回来后对比，同版本→提示更新可能未生效，异版本→显示新版本。**⚠️ 版本字节仅存在于实时 0x30 通知帧；`0x21` 批量记录中的 0x30 保持 2 字节，追加版本会错位致 App 整批丢弃**（v2.5.19，§5.8/§5.15/§4.17）。§4.17 补记 **App 侧 OTA 状态机实现修复**（App build ≤601 未兑现"应答前断连→等待态"转移且超时无断连出口，固件发应答即重启时 App 永久卡发送态；build 602 修复，wire 不变，OTA 联调请用 602+）（v2.5.21，§4.17）。新增 `WiFiDebugMode(0x19)` / `WiFiDebugResult(0x19)`：开启、关闭或查询设备 SoftAP PC 调试模式；设备以 `Enabled + StatusCode` 实时应答，BLE 与 Wi-Fi 必须共存，重启后默认关闭，应答不进入 `0x21` 批次，secure 模式双向均走 `0x7E`（v2.5.22，§4.18/§5.18）。**破坏性变更（v2.5.24）：§3.2 分包头 9B→11B——`Seq`/`Total` 各扩为 2B BE、分包上限 255→65535，双向生效、无兼容窗口，固件收（0x10/0x11/0x15/0x7E…）发（0x21 批量…）两侧分包代码必须同步切换**；`CustomAvatarFrame(0x15)` payload v2 = `SubVersion(0x02) | PNG 文件字节`（≤800×700、保持原图比例、尽力 ≤1MiB，IHDR 自描述宽高），4bpp 96×96 v1 废弃、App 侧量化移除、Spectra-6 色彩映射改由固件渲染时完成（v2.5.24，§3.2/§4.12/§10）。§8.7 新增**问题 5**：固件把 DayPack 偏移 3 的 `DeviceMode` 字节（设置类快照、App 当前实现恒发 0x00=Interactive）误用于门控 §5.7 专注周期唤醒——专注中例行 DayPack 送达即 `Focus refresh heartbeat disabled`，v2.5.23 的息屏后台唤醒链路随之失效（息屏/挂起区间瓶子停更；前台不受影响）。纠正：心跳生命周期只绑设备本地会话上下文与连接存活（`0x11` 建立、完成/跳过/断连/重启停止）；专注实时进度权威 = `0x14 FocusStatus`（Phase 1/2/3 活跃、0=idle）；专注中收到 DayPack 仅后台缓冲、不得改变专注页状态或心跳；断连即会话结束、重连后不凭旧数据复活态 C。§4.7/§5.7/§8.5 同步加注，附固件验收 3 用例。纯文档/固件侧修正，wire 不变（v2.5.25，§4.7/§5.7/§8.5/§8.7）。§3.2 补记 **App 侧重组生命周期**（Device→App 方向）：未完成消息 **5 分钟闲置超时**整条丢弃；被丢弃 MessageId 进入**丢弃名单**（保留 5 分钟、至多 64 条），期间迟到的 `Seq>0` 尾片一律忽略、不重新建槽；`Seq=0` 为**显式重发起点**（解除丢弃标记 + 清同 Id 旧半成品 + 从头重组）——**固件重传必须从 Seq=0 重发整条消息，从中间续传无效**；传输停顿 >5 分钟（如调试断点冻住发送）后同样需整条重发。纯文档 / App 接收端行为，wire 不变（v2.5.26，§3.2/§8.3）。**破坏性变更（v2.5.27）：DayPack Events[] 每条在 `Description` 后追加 1 字节 `Category`**——App 用 AI 依据日历内容把事件归入客户定义的六大类（`0x01`=Deep Work / `0x02`=Meetings / `0x03`=Admin / `0x04`=Deadlines / `0x05`=Wellness / `0x06`=Rest，`0x00`=未分类不画图标）；App 只发类别**信号字节**，六个像素图标为**固件内置美术**（资产：`docs/assets/event-category-icons/`），与伴侣形象/天气图标同为「信号选内置图」架构。固件解析器须同步读取该字节（§7.1 严格解析，flag-day 切换）（v2.5.27，§4.7）。**Category 兜底改点赞（v2.5.28，纯 App 行为、wire 不变）**：客户拍板——AI 归类不了的事件一律按 `0x03`（Administrative & Routine，点赞图标）下发，事件卡不留空图标；`0x00` 保留为合法 wire 值（固件收到即不画图标），App 当前不会发送（v2.5.28，§4.7）。**能量瓶显示封顶 5（v2.5.29，客户 2026-07 决策，纯 App 行为、wire 字节不变）**：`0x14 FocusStatus` 的 `Bottles` 字段是**显示值**，App 侧封顶为 5——满 5 瓶（≈2.5h 连续专注）后恒发 5，不再上涨；**积分（累计能量瓶、场景解锁）按真实值累加、不受此限**（3h=6 瓶照记进积分池）。二者两条独立路径，显示封顶不碰积分源头。固件按收到值渲染即可（最大只会收到 5）（v2.5.29，§4.11）。**破坏性变更（v2.5.30，客户 2026-07-20《电子墨水屏需求》对齐，flag-day 与固件解析器同步切换）：DayPack 两处扩展**——① Events[] 每条在 `Category` 后追加 `EndTime`（1+N bytes，≤8B，"HH:mm"；全天事件空串、跨午夜按 "23:59" 封顶）：固件用于「进行中日程」页**前一日程结束→下一日程开始间隔 <10min/>10min** 的布局分支判定，以及日程概览时间轴的末端标注；② payload 末尾 `FirstUp` 后依次追加三个「每日总结页」（长按完成当日进入）文案字段：`SettlementReview`（≤180B，概况点评——**有死线类日程必提、当日专注 >2h 必提专注时长**，其余 AI 自由发挥；中性面板口吻）、`SettlementQuote`（≤120B，金句/明日鼓励三分支——全部完成→IP 风格庆祝；未完成且日程时长+专注时长 >4h→IP 风格「今天已很努力，只是任务太满」；否则客户指定固定文案）、`TomorrowFirstUp`（≤60B，明日第一件日程「HH:mm 标题」，无明日日程为空串、固件隐藏该行）。`TomorrowFirstUp` 成为 DayPack 最后一个字段，§7.1 严格解析须依次读完（仿真解码器已同步）。同批 App 行为：`DaySummary` 生成规则对齐客户页面一——日程繁忙/紧凑给休息建议，否则提醒喝水（v2.5.30，§4.7/§6.4）。**修订（v2.5.31，客户 2026-07-20 十条答复落地，固件实现 v2.5.30 前生效、合并为一次 flag-day）**：①**撤除 `TomorrowFirstUp`**——客户确认总结页"分3部分"系笔误、实为两部分（概况点评 + 金句），`SettlementQuote` 回归 DayPack 最后一个字段；②边界口径拍板：日程间隔**恰好 10 分钟归情况二**（任务清单布局）、投入**恰好 4 小时归固定文案分支**、庆祝分支要求**当日无未结束日程**、"日程时间"合计**重叠区间不重复计**；③专注页 Tips（`0x11 encouragement`）客户拍板停用——App 恒发空串、字段保留占位；④活跃专注会话 `0x14 Phase` 恒 ≥1（第 0 分钟不再报 idle）；⑤自定义 IP 显示口径：除专注页外全部页面用用户上传单图、不随任务切换，专注页维持内置美术（§4.12）（v2.5.31，§4.7/§4.8/§4.11/§4.12/§6.2/§6.4/§7.1）。

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
| v2.5.12 | 2026-06-29 | **§4.15 澄清屏保帧分包行为（纯文档，wire 不变）**：原写「payload 小，不分包」不准确——屏保 payload 最大约 225B（Quote≤180 + Author≤40 + 5B 头），`Quote`/`Author` 较长或 secure 封装（外层 `0x7E`）后可能超过协商 MTU 写长度，`shouldUseChunkedPacket`（`payloadSize+3 > maxWriteLength`）会触发 §3.2 分包。改为明确：屏保帧**可能单包亦可能分包**，固件须按通用分包重组、不可假设恒为单包。外部复审发现。§4.16 SceneUnlock（1B payload）恒为单包、不受影响 |
| v2.5.13 | 2026-06-30 | **新增 §6.6 字体与排版（纯文档，wire 不变）**：硬件内置两套字库，按**字段语义角色**渲染——`PetDialogue`（宠物气泡）用 Lugrasimo 手写体、其余**所有**中性/数据文本（天气/日期/事件卡/DaySummary/进度/TaskInPage/屏保等）用 Calibri。**字体不走 wire、App 不下发字体选择字节**（字段身份即字体选择器，沿用 §6.5 内容/呈现分离原则）；固件按字段映射字体 + 对 Lugrasimo 缺失字形回退 Calibri。明确「不逐串传字体、不加字体字节」（YAGNI）。回答客户「字体要不要走协议」：不要 |
| v2.5.14 | 2026-07-01 | **§3.5 补记出站 ASCII 净化保证（纯文档，wire 不变）**：App 在编码边界（`appendString` 单一咽喉点）把**所有**出站字符串字段净化为纯可打印 ASCII（`0x20`–`0x7E`）——LLM 常见的弯引号 `’ “ ”` / 长破折号 `— –` / 省略号 `…`、用户手输或日历同步带入的 emoji / 重音字母 / CJK，转写为 ASCII 近似（弯引号→直引号、破折号→`-`、`…`→`...`、`café`→`cafe`）或直接丢弃（无 ASCII 近似者）。**固件收到的任何文本字段恒为纯可打印 ASCII**，§6.6 的 Lugrasimo 缺字回退随之从常态降级为兜底安全网。修复起因：LLM 在 `DaySummary` 写出弯引号 U+2019（UTF-8 `E2 80 99`）→ 硬件渲染成豆腐块 `□`。同时**记 `RequestRefresh(0x20)` 联调期去抖合并**（§8.5）：固件把 0x20 当 ~2s 心跳狂发，App 改用 60s 合并窗把整轮 sync 去抖为 ≤1 次/分（不再硬抑制、保留用户物理刷新；固件停止心跳后按键即时触发）。均为 App 侧行为、wire 不变。ASCII 修复经多轮交叉复审：净化器本体 airtight，复审补捉 `Schedule(0x03)` `StartTime` 的 `DateFormatter` 缺 `en_US_POSIX` locale（波斯/阿拉伯数字区会输出非 ASCII 数字、打偏固定 5 字节字段）——已修 |
| v2.5.15 | 2026-07-02 | **§6.7 新增——面板态判定拍板（纯文档，wire 不变）**：关闭 §6.5 提案要点第 3 条开放问题——**不新增 `PanelMode` 字节**，态 A/B/C 由固件本地状态机判定（本地 RTC + 已收数据 + 用户按键），App 只负责内容与校时。判定优先级：专注中→态 C；有未完成任务→态 B；有事件→态 A；全空→固件空态兜底。原「App 是显示决策方」语义修正为「App 决定**内容**、固件决定**时机与状态**」。依据行业同类分工（Pebble Timeline / BLE CTS / InfiniTime——手机只推结构化数据与时间，屏幕状态是设备本地状态机）；§6.6 早前已按「不引入 PanelMode」行文，本次正式落笔。边界值（晚间结算时段、进行中事件窗口）标注待与固件定稿 |
| v2.5.16 | 2026-07-03 | **§8.5 补记 Time→0x20 反射回路与 DayPack 双发（纯文档 + App 行为，wire 不变）**：联调实测（MsgID 连号、间隔 ~3s、除 PetDialogue/时间外相同的两个完整 DayPack）——固件每收到 `Time(0x05)` 即回一个 `RequestRefresh(0x20)`，而 Time 是 App 每轮 sync 的第一帧，该反射经 App「在途 sync 期间收到的 force 请求收尾补跑」机制放大为背靠背第二轮；恰逢 LLM 对话在两轮之间生成完成（~3s），PetDialogue 变化令 DayPack 指纹变化、第二轮真发 DayPack、硬件双刷屏。**App 侧已修（build 589）**：sync 组包前等待在途对话生成完成（首轮即最终文本），反射补跑轮因内容无变化不再携带 DayPack（退化为 Time/PetStatus 小帧）。**固件侧建议**：收到 Time 不要触发 0x20——0x20 仅保留「开机/唤醒后久无数据」与「用户物理按键刷新」两种意图；7.3寸全刷 ~12s，渲染进行中收到新 DayPack 应合并到下一次刷新而非排队双刷。**§4.7 补记 TopTasks 实现对齐**：规格上限一直是 4寸≤3 / 7.3寸≤5（未变），但 App 端生成与编码此前固定按 4 寸档发 ≤3 条，7.3 寸设备只收到 3 条置顶任务；build 589 起按 App Settings→Hardware Details 配置的屏型发满上限（设备暂无屏型自报通道，需在 App 内手动选择一次），同优先级任务截取顺序确定化（priority→dueDate→id）。wire 格式不变 |
| v2.5.17 | 2026-07-04 | **§4.5 补记 Weather(0x04) 实际发送行为（App build 593 起，wire 不变）**：审计发现 0x04 此前从未被 App 发出（发送函数挂在零调用死路径上，硬件顶栏天气从未更新）；现每轮 sync 无条件发送（紧随 PetStatus 之后）、仅天气变化时单独放行小帧轮（Time/PetStatus/Weather，不发 DayPack、设备不应全刷）、App 无定位权限/取数失败时不发送（设备保持上次显示）、该帧写失败不影响本轮其余帧。固件请按 §4.5 完整字段（含 v2.5.9 HighTemp/LowTemp）验证解析——这是固件首次真实收到该帧。**§8.7 新增问题 4：EnterTaskIn(0x10) payload 未按 §5.3 实现（2026-07-04 联调，build 591）**：实测发 8 字节（首字节 0x00、疑似 idx(4B)+Timestamp(4B) 自创布局），协议要求 Length+UUID+Timestamp；App 解析为空 taskId → 不回 0x11（正确拒绝）、回发 DeviceMode(0x12)=Interactive 解卡（实测设备收到未退页——请实现解卡协作）；附正确 41 字节示例；WheelSelect 中 UUID 发送正确、同一 UUID 放入 EnterTaskIn 即可；CompleteTask/SkipTask 同格式请自查；App 侧已加防御（build 593 起不再出现 Unknown Task/elapsed=65535 怪帧）。另记专注显示推送合流（build 592 起）：0x14(idle) 立即、0x17 仅新解锁、同内容 0x14 2 秒去重——「完成任务连刷三次」消失。wire 均不变 |
| v2.5.18 | 2026-07-09 | **新增 OTAReboot(`0x18`)/OTAResult(`0x18`)——固件升级重启命令**：App→Device 零 payload 触发（§4.17），Device→App 1B 状态码应答（§5.17），按既有方向双义规则复用字节（§2.4/§4.1/§5.2）。固件验证包合法后发应答即直接重启升级（**不等 App 确认**，约 20 秒，BLE 全程关闭），App 侧把"应答到达前先断连"与"收到 `0x00`"同等处理为大概率成功：连接存活时 5 秒无应答重发（至多 3 次判失败），一旦断连即停止重发、转入等待态，抑制该窗口内的连接错误提示，靠 `DeviceWake(0x30)` 确认成功，~90 秒兜底超时后降级为失败提示。安全模式下须走 `SecureEnvelope`（`0x7E`）封装，否则 App 会判定为非法明文包并主动断连（既有安全行为，非本次新增）——当前 dev/TestFlight 均未启用安全模式，不阻塞本轮联调，正式启用前需与固件再次确认双方均已实现封装。升级包本身经设备 WiFi AP 网页上传，App 不参与文件传输，来源：硬件团队《OTA 升级重启命令需求说明》(2026-07-08) |
| v2.5.19 | 2026-07-09 | **DeviceWake(`0x30`) 追加固件版本（前向兼容追加）**：payload 从 `BatteryLevel(1B)` 扩展为 `BatteryLevel(1B)+FwMajor(1B)+FwMinor(1B)+FwPatch(1B)`（设备端 Major.Minor.Patch 三段式版本管理，各段 0-255；示例 `30 04 64 01 02 03` = 电量 100%、固件 v1.2.3）。v2.5.19+ 固件**必填 4B（Length=0x04）**；App 向后兼容 1B（旧固件，版本视为未知）与空 payload（更旧）。版本语义 = 本次启动**实际运行**的版本——升级成功后为新版本，升级失败回滚后为回滚到的旧版本。**⚠️ 仅实时通知帧携带版本：`0x21 EventLogBatch` 中的 0x30 记录保持 2B（type+电量），不得追加版本字节**——App 批量解析按 §5.15 定长走表，多 3 字节即错位并导致**整批丢弃**（离线补传丢失）。用途：关闭 §4.17 已知边界——App 触发 OTA 进入等待态前快照当前版本，收到 DeviceWake 后对比：版本变化→升级生效（显示新版本）；版本相同→提示「更新可能未生效」（回滚与同版本重刷 App 侧不可分，如实提示）；未携带→按版本未知完成。非 OTA 场景 App 亦记录该版本用于 Settings 显示与联调支持。来源：硬件团队 2026-07-09 确认设备端三段式版本管理、DeviceWake 配合变更 |
| v2.5.20 | 2026-07-10 | **§4.2 PetStatus 发送时机补记（App 行为，wire 不变）**：用户在 App 内切换伙伴（内置 IP joy/silas/nova）时，App **立即单发**一帧 0x01 携带新 CharacterId（此前只随节流的整轮 sync 发送，切换后设备最长滞后 1h/4h）；每轮常规 sync 照发不变。固件请确认收到 0x01 后据 CharacterId 即时重绘伙伴形象。**§4.11 FocusStatus 行为描述更新（App 行为，wire 不变）**：打断（interruption）的判定源由「Kirole App 回到手机前台」更正为「专注期间使用了用户自选的分心 App」（iOS 屏幕使用时间监测，方向与产品设计对齐：打开/停留 Kirole 专注界面不算打断、被深度专注拦截页挡下的打开尝试不算打断）；检测未开启（未授权/未选分心 App/监测扩展未上线）时 App 不记打断并在界面明示。SegmentMinutes/EnergyBottles 等 wire 字段与 §9 计算规则（30 分钟=1 瓶、零头作废、时间戳结算）不变 |
| v2.5.21 | 2026-07-12 | **§4.17 App 侧 OTA 状态机实现修复补记（App build 602，wire 不变）**：App build ≤601 存在实现缺陷——规格既定的「应答到达前先断连 → 等待设备回来」转移从未生效（内部断连路由标志布防过晚，sending 期间断连不通知状态机），且 5 秒超时在连接已断时无出口。后果：固件按 §4.17 设计"发应答即重启"时，App 几乎必然永久停在发送态（界面卡 "Sending..."，需杀 App 恢复；**升级本身照常完成**，仅 App 呈现错误、DeviceWake 版本对比结果丢失）。build 602 修复：sending 起即布防断连路由；5 秒超时时连接已断（未连接误触发/写失败）判发送失败而非悬挂；BLE 未连接时禁用升级入口。固件无需任何配合改动，wire 格式不变；**OTA 联调与验收请使用 App build 602+** |
| v2.5.22 | 2026-07-13 | **新增 WiFiDebugMode(`0x19`)/WiFiDebugResult(`0x19`)——PC Wi-Fi 联调开关与状态查询**：App→Device payload 为 1B 命令（`0x00=关闭`、`0x01=开启`、`0x02=查询`）；Device→App 以 `Enabled(1B)+StatusCode(1B)` 实时应答（成功 / 不支持 / 忙 / Wi-Fi 初始化失败 / 非法命令 / 未知错误）。方向双义见 §2.4，帧格式与固件行为见 §4.18 / §5.18。开启后设备进入 SoftAP，PC 访问 `http://192.168.4.1/`；Wi-Fi 与 BLE 必须共存，设备重启后默认关闭。应答只走实时 Notify，**不得写入 `0x21 EventLogBatch`**。secure 模式下请求和应答均封装为 `0x7E SecureEnvelope` |
| v2.5.23 | 2026-07-13 | **§5.7 / §8.5 补记 RequestRefresh(`0x20`) 专注会话周期刷新用途（App 行为 + 固件指引，wire 不变）**：修复「iPhone 息屏后专注页 BLE 中断、能量瓶子不按 30 分钟递增」——iOS 息屏挂起 App 进程，App 内 `0x14 FocusStatus` 的进程内定时推送随之冻结，直到亮屏才补推（实测 elapsed 64→103min、空窗 39min）。iOS 唯一可靠的后台唤醒是外设 Notify：专注期间 BLE 连接保持、App 已订阅 Notify 特征，**固件在专注会话进行中周期性发 `0x20`（建议 ~5 分钟/次）唤醒被挂起的 App**，App 现算并回推最新 `0x14`。App 侧：收到 0x20 且有活跃专注会话时，在 §8.5 的 60s 合并窗**之前**先单独回推 0x14（不被去抖饿死，仅 2s 同内容去重约束）；专注会话进行中不主动断连（保住供唤醒的常驻连接，脉冲式断连只服务空闲期）；被唤醒后先补取挂起期间累积到 App Group 的打断记录再算快照（瓶子按打断归零正确）。0x20 合法意图由两种扩为三种（新增「专注会话周期刷新」）。详见 §5.7 / §8.5 |
| v2.5.24 | 2026-07-14 | **分包头 9B→11B + CustomAvatarFrame(`0x15`) 改传 PNG（双破坏性变更，固件收发两侧需同步更新）**：① §3.2 分包头 `Seq`/`Total` 各由 1B 扩为 **2B BE**（头部 9→11 字节，字段偏移后移 2），分包总数上限 **255→65535**——为承载 ≤1MiB 头像 PNG；**双向生效**：固件接收 App 分包（0x10/0x11/0x15/0x7E 等）与固件发送分包（0x21 批量补传等）都必须切换到 11B 头，**无双格式兼容窗口**（flag-day，本轮联调协调切换）。② §4.12 `0x15` payload v2：`SubVersion(0x02) | PNG 文件字节`（≤800×700、保持原图宽高比、尽力 ≤1MiB），替代 4bpp 96×96 v1（SubVersion `0x01` 废弃、固件无需实现）——App 侧不再做 Spectra-6 量化，色彩映射改由固件在渲染时完成。App 推送前校验 PNG 签名，升级前遗留的 4bpp 资产被丢弃不推送（记日志，用户重建伴侣即恢复）。背景：硬件团队 2026-07 需求「直接收 PNG、保持比例、尽量 1MB 内、最大 800×700」；1MiB 无法装进旧 255 片上限（协商 512B 写长度下单帧至多 ~127KB），故分包头随之升级。§3.2/§4.1/§4.12/§8.3/§10 |
| v2.5.25 | 2026-07-14 | **§8.7 新增问题 5：DayPack 的 DeviceMode 字节被误用于门控 §5.7 专注周期唤醒（固件侧修正，wire 不变）**：2026-07-14 联调实测——专注会话进行中（刚收 `0x14 phase=1`），例行 sync 的 DayPack 解析出 `DeviceMode: Interactive`，固件随即 `Focus refresh heartbeat disabled (300s interval)`，v2.5.23 的息屏后台唤醒链路失效（息屏/挂起区间瓶子停更；前台期间 App 自身推送循环仍在，不受影响）。纠正：① DayPack 偏移 3 的 DeviceMode 是设置类快照、App 当前实现恒发 0x00（`0x01=Focus` 仍为合法 wire 值、保留不废），专注态本就不在 DayPack 内（§4.7 原文），不得据此判定专注/门控心跳；② §5.7 周期唤醒生命周期只绑设备本地会话上下文与连接（收到 `0x11` 建立上下文、进入专注页启动；完成/跳过、断连、本地状态丢失、重启停止），专注实时进度权威=`0x14 FocusStatus`（Phase 1=warmup/2=building/3=deep 活跃、0=idle，按当前未打断段计）；③ 断连即会话结束（App 侧 `reason=disconnected` 同步结束），重连后不得凭缓存 DayPack/旧 `0x14` 复活态 C，退回概览等待新 `0x11`；④ 专注中收到 DayPack 属正常内容轮换，仅后台缓冲、不驱动态切换，退出专注后以随后新一轮 DayPack 为准。附 3 条固件验收用例。§4.7 字段表、§5.7、§8.5 已同步加注 |
| v2.5.31 | 2026-07-20 | **v2.5.30 修订：撤除 `TomorrowFirstUp` + 客户十条答复口径落地（固件实现前修订，与 v2.5.30 合并为一次 flag-day）**：客户逐条答复《电子墨水屏需求》待确认清单——①"总结内容分3部分"确认为**笔误，实为两部分**（概况点评 + 金句/明日鼓励），据 mock 推断的第三尾字段 `TomorrowFirstUp` 撤除，`SettlementQuote` 回归 DayPack **最后一个字段**（固件尚未实现 v2.5.30，撤除零协调成本；仿真解码器同步）；②边界拍板：相邻日程间隔**恰好 10 分钟 → 情况二**（任务清单布局）；投入时长**恰好 4 小时 → 固定文案分支**；**庆祝分支额外要求当日无未结束日程**（晚间还有日程时不出"全部完成"庆祝语——`SettlementData` 进度计数维持"只计已结束"显示口径不变）；"日程时间"合计**重叠/相接区间合并后求和、不重复计**；③"繁忙"不定量化标准，AI 依事件时段判断（digest 自本版携带 "HH:mm-HH:mm" 时段；客户示例：两个连续日程之间应建议 break）；④专注三阶段沿用 v2.5.5 未打断段语义（打断回 warmup）；**活跃会话 `0x14 Phase` 恒 ≥1**——App 修复第 0 分钟/打断清零瞬间误报 idle（固件以 Phase≠0 判会话活跃，§8.7 问题 5 口径）；⑤专注页 Tips 停用：客户拍板不需要，App 对 `0x11 TaskInPage.encouragement` **恒发空串**（字段保留占位，0x11 已联调不动 wire；固件收到空串不渲染该行）；⑥自定义 IP 显示口径（§4.12 加注）：**除专注页外全部页面显示用户上传的单张图、不随任务/标签切换**；专注页维持内置 IP 美术（多图上传暂不支持，2026-07-14 搁置延续）；⑦屏保金句确认为 **AI 结合当日工作原创**（现行实现即是），非名人名言库；⑧概况点评硬规则升级为**输出侧校验**：AI 文本未提任一死线标题或未含专注时长标签时，App 回退恒满足规则的确定性模板 |
| v2.5.30 | 2026-07-20 | **DayPack 双扩展：Events[] 追加 `EndTime` + 末尾追加每日总结页三文案（破坏性，flag-day）**：客户 2026-07-20《电子墨水屏需求》对齐（docs/电子墨水屏需求/）。① 每条 Event 在 `Category` 后追加 `EndTime`（1B 长度前缀 + ≤8B，"HH:mm"；全天事件空串；结束时间跨到次日按 **"23:59" 封顶**——App 是展示口径决策侧）：固件据此判定「进行中日程」页布局分支（**前一日程结束→下一日程开始间隔 <10 分钟 → 显示当日完成比例 + 事件卡；>10 分钟 → 显示下一日程 + 任务清单**，间隔算术在固件本地做）并标注页面一日程概览时间轴的事件区段。② `FirstUp` 后依次追加 `SettlementReview`（≤180B）/ `SettlementQuote`（≤120B）/ `TomorrowFirstUp`（≤60B）——「每日总结页」（页面二**长按=完成当日**进入，再次长按返回防误触；无新增入站字节，硬件进入页面可用既有 `0x20` 拉新，显示为最近一轮 sync 推送的文本）三段内容：概况点评（App 生成规则：**有 `0x04` 死线类日程必提；当日专注累计 >2h 必提专注时长**，兜底模板确定性满足）、金句/明日鼓励（三分支：全部完成→IP 人格庆祝语；未完成且**日程时长+专注时长 >4h**→IP 风格「今天已很努力，只是任务定多了，明天可减量」；否则固定文案 "When the schedule is full, plan fewer tasks to leave room for focus."）、明日第一件日程（"HH:mm 标题"，同 FirstUp 格式；空串=固件隐藏该行）。`TomorrowFirstUp` 现为 DayPack **最后一个字段**，§7.1 严格解析须依次读完三个尾字段（仿真解码器 `parseDayPack` 已同步，710 tests 全绿）。③ 同批 App 行为（wire 不变）：`DaySummary` 提示规则对齐页面一——繁忙/紧凑→休息建议、空闲→提醒喝水。所有文案 English-only + ASCII 净化（§3.5）不变 |
| v2.5.29 | 2026-07-20 | **能量瓶显示封顶 5（纯 App 行为，wire 字节不变）**：客户 2026-07 决策——硬件专注页能量瓶槽位设计最多 5 个，`0x14 FocusStatus` 的 `Bottles` 字段（显示值）由 App 侧封顶为 **5**：一次会话连续专注满 5 瓶（≈2.5h）后本字段**恒发 5**、不再随真实瓶子数上涨（字节仍 clamp 0-255）。**积分（累计能量瓶 / 场景解锁 80 瓶/场景）不受此上限影响**——会话结束按**真实**瓶子数（如 3h=6）累加进积分池。显示与积分是两条独立路径（显示封顶只作用在 `0x14` 出口 `syncFocusHardwareDisplay`，`session.earnedEnergyBottles` 积分源头不动）。固件侧**无需改动**：本字段最大只会收到 5，按收到值渲染即可。背景：此前 App 发真实值（可达数十）+ 调试构建「Add 30 minutes / 加速」开关会把显示灌破 5、视觉溢出。§4.11 |
| v2.5.28 | 2026-07-17 | **Category 兜底改点赞（纯 App 行为，wire 不变）**：客户拍板——AI 归类不了（AI 不可用/输出非法且关键词启发式未命中）的事件，App 一律按 `0x03`（Administrative & Routine，点赞图标）下发，事件卡不留空图标。`0x00` 保留为合法 wire 值：固件收到仍应**不画图标、其余照常渲染**（前向兼容），但 App 当前不会发送。固件侧无需改动。§4.7 Category 表 0x00 行同步加注 |
| v2.5.27 | 2026-07-17 | **DayPack Events[] 每条追加 1 字节 `Category`（破坏性，flag-day）**：App 用 AI 依据日历内容把事件归入客户定义的六大类（《图标对应关系》文档，2026-07-17）：`0x01`=Deep Work（沙漏）/ `0x02`=Meetings & Synced（对话气泡）/ `0x03`=Administrative & Routine（点赞）/ `0x04`=Critical Deadlines（对勾）/ `0x05`=Bio-Habits & Wellness（爱心）/ `0x06`=Rest & Recharge（笑脸），`0x00`=未分类（固件**不画图标**、其余照常渲染）。字节位置：每条 Event 的 `Description` 之后（§4.7「Event 条目」表）。App 只发**信号字节**，六个像素图标为**固件内置美术**（客户提供的资产已入库 `docs/assets/event-category-icons/`，1:1 交付固件）——与伴侣形象 / 天气图标同为「信号选内置图」架构。App 侧实现：一次批量 AI 分类 + 按事件缓存（跨 sync 轮不重复调用）+ 关键词启发式兜底；AI 调用失败后进入 10 分钟冷却，冷却期直接走启发式，期满自动重试升级。固件解析器须同步读取该字节（§7.1 严格解析——读完 Description 必须再读 1 字节 Category，否则整体错位），与固件 DayPack 解析更新一并 flag-day 切换。§4.7 |
| v2.5.26 | 2026-07-16 | **§3.2 补记 App 侧重组生命周期（纯文档，wire 不变）**：① 未完成消息**闲置 5 分钟**（自最后一个有效分片起算）即整条丢弃、释放槽位（记 App 日志）；② 因闲置超时 / 超 256 KiB 上限 / 8 槽占满被丢弃的 MessageId 进入**丢弃名单**（保留 5 分钟、至多 64 条，超出逐出最旧），名单内 MessageId 的 `Seq>0` 分片一律忽略、不重新建槽——防止迟到尾片以残缺状态复活消息；③ `Seq=0` 为**显式重发起点**：解除丢弃标记、清空同 MessageId 旧半成品、从头重组（同时杜绝复用在途 Id 时"新头拼旧尾"错拼出脏数据）。**固件重传须从 Seq=0 重发整条消息，从中间 Seq 续传无效**；传输停顿 >5 分钟（典型：固件调试断点冻住发送）后需整条重发，现象否则表现为"分片发了但 App 无响应"。App 接收端（Device→App，0x21 批量补传等分包消息）行为；固件接收端（App→Device 方向）可参照同款策略。§8.3 固件建议表同步加行 |

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
| `0x18` | OTAReboot | OTAResult |
| `0x19` | WiFiDebugMode | WiFiDebugResult |
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

> **⚠️ v2.5.24 破坏性变更（无兼容窗口）：** 头部由 9 字节扩为 **11 字节**——`Seq`/`Total` 各由 1B 扩为 **2B Big Endian**，其后字段偏移整体后移 2；分包总数上限 **255→65535**（为承载 §4.12 的 ≤1MiB 头像 PNG）。**双向生效**：固件接收 App 分包（0x10/0x11/0x15/0x7E 等）与固件发送分包（0x21 批量补传等）都必须同步切换到 11B 头。App build ≥606 只收发 11B 头；新旧混跑会互相解不出分包，请与 App 版本协调 flag-day 切换。

当 payload 超过 BLE MTU 时，使用 11 字节头部将其拆分为多个分包：

```
+--------+------------+------------+------------+------------+----------+---------+
| Type   | MessageId  | Seq        | Total      | PayloadLen | CRC16    | Payload |
| 1 byte | 2 bytes BE | 2 bytes BE | 2 bytes BE | 2 bytes BE | 2 bytes  | N bytes |
+--------+------------+------------+------------+------------+----------+---------+
  offset:      1..2        3..4         5..6         7..8       9..10      11..
```

| Field      | Size    | 描述 |
|------------|---------|------------------------------------------------------|
| Type       | 1 byte  | 命令类型标识符（同 Section 3.1） |
| MessageId  | 2 bytes | 消息标识符（Big Endian），同一消息的所有分包共享 |
| Seq        | 2 bytes | 分包序号（Big Endian，从 0 开始）（v2.5.24 由 1B 扩为 2B） |
| Total      | 2 bytes | 分包总数（Big Endian）（v2.5.24 由 1B 扩为 2B） |
| PayloadLen | 2 bytes | 本分包的 payload 长度（Big Endian） |
| CRC16      | 2 bytes | 本分包 payload 的 CRC16-CCITT-FALSE 校验值（Big Endian） |
| Payload    | N bytes | 分包 payload 数据 |

**头部大小：** 共 11 字节（v2.5.24 前为 9 字节）

**CRC16 参数（不变）：**
- 算法：CRC16-CCITT-FALSE
- 多项式：`0x1021`
- 初始值：`0xFFFF`
- XOR out：`0x0000`
- Reflect in/out：`false`

**重组：** 接收端收集所有相同 MessageId 的分包，按 Seq 排序，验证每个分包的 CRC16，然后拼接 payload 以重建完整消息。

**使用场景：** DayPack (0x10)、TaskInPage (0x11)、CustomAvatarFrame (0x15) 及其他大 payload 使用此格式。简单命令（PetStatus、Weather、Time）使用 Section 3.1 的 3 字节头部。

**联调边界：** 分包总数上限为 **65535**（v2.5.24 前为 255）。App 侧最多同时保留 8 个未完成 MessageId，**Device→App 方向**单个重组 payload 上限仍为 256 KiB（0x21 批量补传远小于此，勿因头像帧误抬——≤1MiB 头像是 App→Device 方向，不经过 App 侧重组器）；超过限制的分包会被丢弃（v2.5.2 起丢弃会记 App 侧日志，按 MessageId 去重）。**BLE 断连时 App 清空全部未完成重组状态**（v2.5.2）——固件重连后用新 MessageId 重发即可，不会撞上断连前残留的半成品槽位。App 侧连接内的超时与丢弃规则见下段「App 侧重组生命周期」（v2.5.26）；App 侧只验证每包 CRC 和完整重组，不发送分包级 ACK。

**App 侧重组生命周期（v2.5.26，Device→App 方向，wire 不变）：**

1. **闲置超时 5 分钟**：未完成消息自**最后一个有效分片**到达起，连续 5 分钟无新分片 → 整条丢弃、释放槽位（记 App 日志）。取值依据：入站单条上限 256 KiB，正常传输秒级完成；5 分钟只在链路异常/发送端冻结时才会触发。
2. **丢弃名单（tombstone）**：因闲置超时、超 256 KiB 上限或 8 槽占满而被丢弃的 MessageId 进入丢弃名单，保留 **5 分钟**、至多 **64 条**（超出时逐出最旧）。名单内 MessageId 再收到 `Seq>0` 分片**一律忽略、不重新建槽**——迟到尾片不能以残缺状态复活消息。
3. **`Seq=0` = 显式重发起点**：任何 MessageId 收到 `Seq=0` 分片即（a）解除其丢弃标记、（b）清空同 Id 的旧半成品、（c）从头开始重组。此规则同时保证：发送端复用在途 MessageId 重发时，不会出现"新消息头拼上旧消息尾"的错拼脏数据。

**固件侧对应要求：** 重传（无论何种原因）**必须从 `Seq=0` 重新发送整条消息**，从中间 Seq"续传"无效——尾片会被丢弃名单吞掉或被视为孤片。特别地：传输中途停顿超过 5 分钟（典型场景：固件挂调试器断点把发送冻住）后再补发剩余分片是无效的，现象表现为"分片已发但 App 毫无响应"；从 `Seq=0` 整条重发即可恢复。本节为 App 接收端行为；固件接收端（App→Device 方向）可参照同款策略实现 §3.2 末尾「丢包处理」的超时丢弃。

**大帧传输预估与 MTU 建议（v2.5.24）：** 以最坏情况 ≤1MiB 头像帧（§4.12，payload ≤1,048,577B）为例：协商 512B 写长度时每片 payload = 512−11 = 501B → **≈2093 片**；叠加 App 侧写限流（§8.5，20 次/秒）**理论 ≈105 秒、实际预期 1–2 分钟**——固件看到 0x15 分包流持续约 2 分钟属正常，不是卡死。**强烈建议固件协商大 MTU**（写长度 ≥512）；写长度过小会使片数超过 65535，此时 App 侧组包直接报错、该帧转入 §4.12 的待重发队列，**不会发出半截消息**。

**长消息与其他帧交错（v2.5.24）：** 头像帧长传输期间，DayPack / Time 等其他业务帧可能以**不同 MessageId** 交错到达。固件重组必须严格按 MessageId 分槽、支持至少 2 条并发未完成消息，不得假设一条消息的分包连续独占信道。

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
| `0x15` | CustomAvatarFrame | 推送用户自定义伴侣头像 **PNG**（≤800×700、保持原图比例、尽力 ≤1MiB；v2.5.24 起 SubVersion `0x02`，详见 §4.12） |
| `0x16` | Screensaver  | 屏保金句/明信片业务帧（替代旧 `0xAA 01 02` 开发命令，secure 模式可发；详见 §4.15） |
| `0x17` | SceneUnlock  | 场景解锁业务帧（替代旧 `0xAA 01 01` 开发命令，secure 模式可发；详见 §4.16） |
| `0x18` | OTAReboot | 触发固件升级重启（零 payload；固件校验升级包合法后发应答并重启进入升级，不等待 App 确认；详见 §4.17） |
| `0x19` | WiFiDebugMode | 开启、关闭或查询设备的 PC Wi-Fi 调试模式（1B 命令；详见 §4.18） |
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

> **发送时机（v2.5.20）**：本帧每轮常规 sync 固定发送（Time 之后、Weather 之前）；此外用户在 App 内**切换伙伴（内置 IP）时立即单发一帧**（不等 1h/4h 同步节流窗，与自定义头像 0x15 的立即推送同待遇）。固件收到后应据 `CharacterId` 即时重绘伙伴形象。

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

> **v2.5.17 发送行为补记（App build 593 起，固件请注意——这是固件首次真实收到本帧）**：审计发现此前 0x04 **从未被 App 发出**（发送函数挂在一条零调用的死路径上，硬件顶栏天气从未被更新过）。自 build 593 起：① 每轮 sync **无条件发送**本帧（约 10 字节，与 PetStatus 同策略），紧随 PetStatus(0x01) 之后、DayPack(0x10) 之前；② **仅天气变化**时 App 会单独放行一轮"小帧轮"（Time/PetStatus/Weather，DayPack 内容未变则不发 0x10——设备不应因此全刷）；③ App 无定位权限或取数失败（仅有占位数据）时**不发送**本帧，设备保持上次显示；④ 本帧写失败不影响该轮其余帧（App 侧独立容错）。请按上方 v2.5.9 完整字段（含 HighTemp/LowTemp）验证解析。

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
| 3      | DeviceMode             | 1 byte      | -          | 0x00=Interactive, 0x01=Focus。**设置类快照（App 当前实现恒发 0x00）**；不得用于判定专注态或门控 §5.7 周期唤醒——专注进行中的权威信号是 `0x14 FocusStatus`（见 §8.7 问题 5，v2.5.25） |
| 4      | FocusChallengeEnabled  | 1 byte      | -          | 0x00=禁用, 0x01=启用 |
| 5      | PetDialogue            | 1 + N bytes | 120 bytes  | **宠物气泡**：= App `currentPetDialogue`（阶段感知，早安/陪伴/结算同一句变脸，见 §6.5）|
| ...    | EventCount             | 1 byte      | -          | 今日事件数（0-N）|
| ...    | Events[]               | Variable    | -          | 事件列表（见下「Event 条目」）|
| ...    | TaskCount              | 1 byte      | -          | 置顶任务数量（0-5，取决于屏幕尺寸）|
| ...    | TopTasks[]             | Variable    | -          | 置顶任务（见下，4寸≤3 / 7.3寸≤5）|
| ...    | SettlementData         | Variable    | -          | 进度/专注数值（见下，**已无文本消息**）|
| ...    | DaySummary             | 1 + N bytes | 180 bytes  | **一天总结（框②）**：情绪向、**只谈日程**（不含 to-do 任务）的概览 + 一条建议——**繁忙/紧凑给休息建议，空闲则提醒喝水**（v2.5.30 规则）；追加在 `SettlementData` 之后（v2.5.7，见下注）。空串表示尚未生成 |
| ...    | FirstUp                | 1 + N bytes | 60 bytes   | **下一项（框③）**：「First up:」内容——下一个未来事件「HH:mm 标题」（全天事件仅标题），无未来事件则置顶任务标题，皆无则空串。App 算好下发（v2.5.8，在 DaySummary 之后，见下注）|
| ...    | SettlementReview       | 1 + N bytes | 180 bytes  | **每日总结页·概况点评**（v2.5.30）：中性面板口吻点评今日日程+专注——**有死线类日程必提、当日专注 >2h 必提专注时长**，其余 AI 自由发挥。空串表示尚未生成（见 §6.4）|
| ...    | SettlementQuote        | 1 + N bytes | 120 bytes  | **每日总结页·金句/明日鼓励**（v2.5.30）：三分支——全部完成（且当日无未结束日程，v2.5.31）→IP 风格庆祝；未完成且日程+专注 >4h→IP 风格「努力了只是任务太满」；否则固定建议文案（见 §6.4）。**DayPack 当前最后一个字段**（v2.5.31，见下注）|

> **v2.5.0 破坏性变更**：删除旧字段 `MorningGreeting / DailySummary / FirstItem / CurrentScheduleSummary / CompanionPhrase`，收敛为单字段 `PetDialogue`；新增带描述的 `Events[]`（旧协议缺此能力）。固件解析器须按本表重写。

> **v2.5.7 追加（新增字段，严格解析）**：在 payload **末尾**追加 `DaySummary`（框②「一天总结」，≤180 字节，1 字节长度前缀 + UTF-8）。注意：按 §7.1，wire 解析是**严格**的（尾部多余字节视为格式错误），故 `DaySummary` 是 DayPack 的**尾部必读字段**（其后还有 `FirstUp`，v2.5.8）、不是可忽略的可选尾巴，固件须按顺序读完尾部字段才算到达 payload 末尾。无兼容风险是因为**固件 DayPack 解析尚未上线**——会直接按含 `DaySummary` 的完整 v2.5.7 布局实现；置于定长 `SettlementData` 之后只是让既有字段偏移保持稳定。语义：与 `PetDialogue`（宠物口吻单句）**互补**——`DaySummary` 是**面板上的一天概览段落**，情绪向、只谈日程、附一条实用建议（如「11:30 先休息，避开正午会议」）。App 侧由 `DayPackGenerator` 喂**今日事件明细（时间/标题）**经 LLM 生成，无 key/离线时兜底为「N events today」计数模板。背景见 §6.5（v2.5.0 曾把多段文本收敛为单气泡，框②的一天总结此次作为**面板文本字段**复活，不回退单气泡决策）。

> **v2.5.8 追加（FirstUp，框③）**：在 `DaySummary` **之后**再追加 `FirstUp`（≤60 字节，1 字节长度前缀 + UTF-8），承载设计稿页面一框③的「First up:」内容。值由 **App 算好下发**：取**下一个未来事件**（startTime > 当前时刻、最早的一个）格式化为「HH:mm 标题」（全天事件仅标题）；无未来事件则取**置顶（最高优先级未完成）任务**标题；皆无则空串。由 App 算而非固件合成，是沿用 §6.5「App 是显示决策方」——「相对当前时刻的下一个」是 App 侧时间逻辑，固件只渲染。（~~FirstUp 为最后一个字段~~ 自 v2.5.30 起其后还有三个尾字段，见下注。）

> **v2.5.30/v2.5.31 追加（每日总结页两文案，严格解析）**：在 `FirstUp` **之后**依次追加 `SettlementReview`（≤180B）、`SettlementQuote`（≤120B），均为 1 字节长度前缀 + UTF-8，承载客户《电子墨水屏需求》（2026-07-20）「每日总结页」两段内容（客户确认"分3部分"系笔误；页面流转与触发见 §6.4 及固件功能规格文档）。生成规则：`SettlementReview` 中性面板口吻，**有 `Category=0x04` 死线类日程必提该日程、当日专注累计 >2h 必提专注时长**——v2.5.31 起为**输出侧校验**：AI 文本不满足即回退恒满足规则的确定性模板；`SettlementQuote` 三分支——全部完成（任务+已结束日程，**且当日无未结束日程**，v2.5.31）→ IP 人格庆祝语；未完成且「今日日程时长（重叠区间合并计）+ 专注时长」>4h → IP 风格表达「今天已很努力，只是任务定多了，明天可减量」；否则（含恰好 4h）客户指定固定文案。文案随每轮 sync 更新（每日总结页显示的是最近一轮推送的文本；硬件进入该页可用既有 `0x20` 拉新，**无新增入站字节**）。`SettlementQuote` 现为 DayPack **最后一个字段**（v2.5.30 曾有第三尾字段 `TomorrowFirstUp`，客户拍板两部分后于 v2.5.31 在固件实现前撤除），同 §7.1 严格解析：固件须依次读完这两个尾字段才到 payload 末尾（仿真解码器 `parseDayPack` 已同步）。

**Event 条目：**

| Offset | Field       | Size        | Max Length | 描述 |
|--------|-------------|-------------|------------|--------------------------|
| 0      | Time        | 1 + N bytes | 8 bytes    | 起始时间 "HH:mm"（全天事件为空串）|
| ...    | Title       | 1 + N bytes | 40 bytes   | 事件标题 |
| ...    | Description | 1 + N bytes | 120 bytes  | 事件描述（设计稿事件卡正文）|
| ...    | Category    | 1 byte      | -          | 事件类别（v2.5.27，AI 打标，见下表；`0x00`=未分类，不画图标）|
| ...    | EndTime     | 1 + N bytes | 8 bytes    | 结束时间 "HH:mm"（v2.5.30；全天事件空串；**跨午夜按 "23:59" 封顶**）。用途：「进行中日程」页 <10min/>10min 间隔分支判定 + 页面一时间轴事件区段标注 |

> **v2.5.27 追加（Category，破坏性）**：每条 Event 在 `Description` 后追加 1 字节 `Category`——App 用 AI 依据日历内容把事件归入客户定义的六大类（《图标对应关系》文档，2026-07-17），固件据此在事件卡上绘制对应**内置**图标。像素图标资产在仓库 `docs/assets/event-category-icons/`（客户提供，1:1 交付固件）；App **不传图片字节**，与伴侣形象（§4.2 CharacterId）/ 天气图标（§4.5 Condition）同为「信号选内置图」架构。分类不可得（AI 不可用且关键词兜底未命中）时，App 发 `0x03`（Administrative & Routine，点赞图标）——**客户拍板（2026-07-17，v2.5.28）：归类不了的一律按点赞归类**，事件卡不留空图标；`0x00` 仍为合法 wire 值（固件收到即不画图标、其余照常渲染），App 当前不会主动发送（前向兼容保留）。AI 调用失败后进入 10 分钟冷却，冷却期直接走关键词启发式，期满自动重试并在服务恢复后升级分类。同 §7.1 严格解析：固件读完 `Description` 后**必须**再读这 1 字节，少读即整体错位（仿真解码器 `parseDayPack` 已同步）。

> **v2.5.30 追加（EndTime，破坏性）**：每条 Event 在 `Category` 后追加 `EndTime`（1 字节长度前缀 + ≤8B "HH:mm"）。语义与 `Time` 对称：同一格式化口径（en_US_POSIX）、全天事件空串；结束时间落在开始时间之后的日历日（跨午夜）时按 **"23:59" 封顶**——App 是展示口径决策侧（§6.5）。固件用途：① 客户「进行中日程」页两种布局的判定输入——**前一日程 `EndTime` 到下一日程 `Time` 的间隔 <10 分钟 → 情况一（显示当日完成比例，`SettlementData.TasksCompleted/TasksTotal`）；≥10 分钟 → 情况二（下一日程 + 任务清单；恰好 10 分钟归此侧，客户确认默认口径 2026-07-20）**，"HH:mm"→分钟的比较算术在固件本地做；② 页面一日程概览时间轴上标注事件区段/末端时刻。同 §7.1 严格解析：固件读完 `Category` 后**必须**再读这个长度前缀字符串，少读即整体错位（仿真解码器 `parseDayPack` 已同步）。

**Category 六大类映射（v2.5.27）：**

| Category | 类别 | 内置图标 | 典型内容 |
|----------|------|----------|----------|
| `0x00` | 未分类（保留值） | （不画图标） | 固件收到即不画图标；**App 自 v2.5.28 起不再发送**——归类不了的按 `0x03` 点赞下发（客户拍板 2026-07-17） |
| `0x01` | Deep Work（深度工作/核心生产力） | 沙漏 | 写代码、写文案、做设计、分析数据 |
| `0x02` | Meetings & Synced（会议与协同沟通） | 对话气泡 | 同步会、对数据、客户对齐、面试 |
| `0x03` | Administrative & Routine（行政日常琐碎） | 点赞 | 清邮件、填报表格、处理询盘 |
| `0x04` | Critical Deadlines（硬性死线与交付） | 对勾 | 项目上线、合同/还款截止日 |
| `0x05` | Bio-Habits & Wellness（生物钟习惯与健康） | 爱心 | 拉伸、喝水、维他命、睡前准备 |
| `0x06` | Rest & Recharge（充能与私人生活） | 笑脸 | 午休、午餐、看书、陪宠物 |

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
  - 空字符串 = 单字节 `0x00`（例如尚未生成时的 `DaySummary`、全天事件的 `Time`/`EndTime`）。
  - `TopTasks` 为 0 条时 `TaskCount = 0x00`，其后**没有**任何 TopTask 子结构。
  - `SettlementData` 只含定长数值字段（文本消息 v2.5.0 已删除）；其后的 `DaySummary` / `FirstUp` / `SettlementReview` / `SettlementQuote` 四个尾字段可为空串，但长度前缀字节恒在、必须依次读取。
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
| ...    | Encouragement        | 1 + N bytes | 50 bytes   | 鼓励消息（Tips）。**v2.5.31 起客户拍板停用：App 恒发空串**（字段保留占位、wire 不变——0x11 已联调；固件收到空串不渲染该行） |
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
| 0      | Phase        | 1 byte      | 专注阶段（按**当前未打断段**计，打断后退回 warmup）。**v2.5.31：会话活跃时恒 ≥1**——会话第 0 分钟与打断清零瞬间按 warmup 发送，`0`=idle 仅表示**无会话**（固件以 Phase≠0 判会话活跃，§8.7 问题 5 口径）：0=idle, 1=warmup(0-5m), 2=building(6-15m), 3=deep(16m+) |
| 1      | Bottles      | 1 byte      | 本会话已收集的能量瓶子数（**显示值**）：按未打断段各自 floor(段÷30) 累计，打断重置正在装填的进度、零头不跨打断合并。**App 侧显示封顶 5**（满 5 后本字段恒发 5，见下方说明），字节仍 clamp 0-255 |
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

> **打断判定（v2.5.20 更正，App 行为、wire 不变）**：上表「被手机打断」的判定源更正为——**专注期间使用了用户自选的分心 App**（iOS 屏幕使用时间监测，清单复用深度专注的应用选择）。打开/停留在 Kirole 的专注界面**不算**打断；被深度专注拦截页挡下的打开尝试**不算**打断。检测未开启（未授权屏幕使用时间 / 未选分心 App / 监测扩展未上线）时 App **不记打断**，并在专注界面明示检测未开启。此前实现以「Kirole 回到前台」为打断信号，与产品设计相反，已废弃、不保留回退路径。固件侧无需任何配合改动。

> **能量瓶显示封顶 5（v2.5.29，客户 2026-07 决策，App 行为、wire 字节不变）**：`Bottles` 字段是**显示值**，App 侧封顶为 **5**——一次会话连续专注满 5 瓶（≈ 2.5 小时）后，本字段**恒发 5**、不再随真实瓶子数上涨。**积分（累计能量瓶、场景解锁）不受此上限影响**：会话结束时按**真实**瓶子数（如 3 小时=6）累加进积分池（80 瓶/场景解锁照算）。二者是两条独立路径——显示封顶只作用在 `0x14` 出口，不碰积分源头。**固件侧无需改动**：本字段最大只会收到 5，按收到值渲染即可（无需自行 min）。背景：硬件专注页能量瓶槽位设计为最多 5 个，此前 App 发真实值（可达数十）会视觉溢出；调试构建的「Add 30 minutes / 加速」开关也曾把它快速灌破 5。

---

### 4.12 CustomAvatarFrame (0x15)

App→Device 推送用户自定义伴侣的头像 **PNG**：用户在 App 内选用自定义伴侣形象时，将其照片处理为 PNG 推送到 E-ink 显示。**v2.5.24 起按硬件团队要求（2026-07）改传 PNG 文件**：App 侧不再做 Spectra-6 量化与 4bpp 打包，**色彩量化 / 抖动由固件在渲染时完成**；App 只保证 PNG 格式、尺寸与字节预算（见下）。App 端已实现并在运行（用户选择/创建自定义伴侣、以及 BLE 重连补推时发送）。

**字节复用（既有规则，仅需按方向分发）：** `0x15` 出站=CustomAvatarFrame、入站=ViewEventDetail（§5.11），与 `0x10`~`0x14`、`0x20` 等的方向双义规则完全一致（出站走 `FFE1` Write、入站走 `FFE2` Notify，另见 §2.4 复用值表），固件按方向 / 特征值分发即可。

**传输方式：** 经 §3.2 分包帧发送（**11 字节分包头**，`type=0x15`）；固件按分包重组后得到下方完整 payload。**不以简单包形式出现。** 最坏情况 ≤1MiB payload ≈ 2093 片 @501B/片、传输 1–2 分钟（详见 §3.2 大帧传输预估）；期间其他业务帧可能以不同 MessageId 交错到达。

**重组后 Payload 结构（v2，SubVersion 0x02）：**

| Offset | Field      | Size            | 描述 |
|--------|------------|-----------------|------|
| 0      | SubVersion | 1 byte          | 格式版本，当前固定 `0x02`（PNG 载荷）。`0x01`（4bpp 96×96）已废弃，固件**无需实现**；SubVersion ≠ `0x02` 时应丢弃整帧 |
| 1      | PNGFile    | N ≤ 1,048,576 B | 完整 PNG 文件字节，首 8 字节恒为 PNG 签名 `89 50 4E 47 0D 0A 1A 0A`；宽高由 PNG IHDR 自描述 |

总 payload 长度 ≤ `1 + 1,048,576 = 1,048,577` 字节。

**App 侧对 PNG 的保证：**
- **尺寸 ≤ 800×700**（宽 ≤800、高 ≤700），**保持原图宽高比**——不裁方形、不放大，仅等比缩小装入外接框；极端长宽比图片会得到极扁/极窄的合法尺寸（如 4000×100 → 800×20）。固件按实际 IHDR 尺寸在显示区内自行布局（居中/留白等由固件决定）。
- **字节数尽力 ≤1MiB（硬上限）**：编码超预算时 App 按 ×0.9 逐步缩小重编码直至达标，绝不发送超过 1,048,576 字节的 PNG。
- **8-bit sRGB RGBA**：可能含 **alpha 通道**，固件渲染建议按白底合成；不会出现宽色域/16-bit 通道。
- 方向已归一（EXIF orientation 已烘焙进像素），固件无需处理 EXIF。

**真相源：** 出站字节见 `Core/BLE/BLEProtocol.swift` 的 `BLEDataType.customAvatarFrame`；编码见 `BLEDataEncoder.encodeCustomAvatarFrame`；图片处理见 `AvatarImageProcessor`（800×700 / 1MiB / ×0.9 收缩常量均在此）。

**App 侧重发策略（联调相关，v2.5.1）：** 自定义头像帧由 App 在切换伴侣或 BLE 重连后尝试推送。若推送失败（硬件未就绪 / 固件尚未实现 `0x15`），App 会把该伴侣标记为待重发，并在后续每轮 sync 重试，采用**退避降频**而非固定次数硬上限：

- 前 5 轮 sync：每轮都重发（覆盖临时抖动，硬件恢复后快速补上）。
- 之后：每 20 轮 sync 才重发一次（固件长期不接受 `0x15` 时，不会每轮 sync 刷屏）。
- **永不永久放弃**：只要仍处待重发状态，就始终保留周期性重试；硬件一旦开始接受 `0x15` 即自愈。
- 成功推送、或用户切换到其它伴侣后，重试计数清零。

> 联调提示：固件未实现 `0x15` 期间，会看到 App 偶发重发一帧失败的 `0x15`——这是预期内的低频自愈重试，**不是 bug**；固件实现 `0x15` 后该帧即被接受、重发自然停止。真相源：`AppState+CustomCompanions.swift` 的 `shouldAttemptCustomAvatarFlush` / `flushPendingCustomCompanionPushIfNeeded`。

**旧资产护栏（v2.5.24）：** App 在每次推送前校验持久化头像资产的 **PNG 签名与 ≤1MiB 上限**——v2.5.24 之前安装的 App 本地可能残留旧 4bpp 像素资产，此类资产（以及任何超限文件）**不会被发出**（App 记日志、清除待重发标记、放弃推送；用户重新创建该伴侣即恢复正常推送）。固件不会收到 4bpp 载荷伪装成 `0x02` 的帧，也不会收到超过 1,048,576 字节的 PNG。

**⚠️ secure 模式下 0x15 暂不可用（开放问题，启用安全模式前须与固件定版）：** §3.4 的 `0x7E SecureEnvelope` 长度字段为 2 字节（≤65,535B），结构上装不下 ≤1MiB 的头像 payload；且信封时间戳容差 120 秒，小于本帧 1–2 分钟的传输时长。App 侧已防御：secure 模式下发送超过 65,535B 的信封 payload 会**抛错进入待重发队列**（不会崩溃、不会发出损坏帧），即 secure 模式启用后头像帧会持续待发直到大帧安全封装定版（候选方案：长度字段扩 4B / 分片签名 / 0x15 豁免走明文——需双方共同确认）。当前联调按明文运行，不受影响。

**链路机密性（已知取舍，记录在案）：** 本协议整体为明文设计（secure 模式亦仅 HMAC 完整性签名、不加密载荷），头像 PNG 以明文经 BLE 分包传输、蓝牙抓包可还原。产品语境：头像最终公开显示于桌面 E-ink 屏；如未来需要链路机密性，走 BLE 配对/链路层加密或引入加密信封，均属协议演进项。

---

> **v2.5.31 显示口径（客户 2026-07-20 答复）**：自定义 IP 激活时，**除专注页外的全部页面**（早安/概览/每日总结/屏保等）显示本帧下发的用户单张图，**不随任务/标签切换**（当前仅支持单图上传）；**专注页维持内置 IP 美术**（多姿态图未支持，2026-07-14 搁置延续）——专注页显示哪个内置 IP 以最近一次 `0x01 PetStatus.CharacterId` 为准。用户切回内置 IP 时 App 发送新 `0x01`，固件应以最后收到的选择为准恢复内置形象渲染。

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

> **传输：** payload 较短时走简单包 `Type(0x16) + Length + Payload`；但 Quote（≤180B）+ Author（≤40B）较长时，整体可能超过协商的 MTU 写长度，此时按 §3.2 **分包**（11 字节分包头，v2.5.24）；固件须按通用分包重组——**不可假设屏保帧恒为单包**。secure 模式下整体先由 `0x7E SecureData` 封装，再按需对**外层 `0x7E`** 分包。**真相源：** 出站字节见 `Core/BLE/BLEProtocol.swift` 的 `BLEDataType.screensaver`；编码见 `BLEDataEncoder.encodeScreensaver`；测试见 `BLESceneUnlockTests.screensaverFrameEncoding`。
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

### 4.17 OTAReboot (0x18)

App→Device 触发固件升级重启。**升级包本身不经此帧传输**——固件预先通过设备自身的 WiFi AP（`http://192.168.4.1/`）网页文件服务器接收 `update.bin`（App 不参与，来源：硬件团队《OTA 升级重启命令需求说明》2026-07-08）；`0x18` 只是"检查已就位的包并重启进入升级"的触发信号。

**Payload：** 无（Length = 0）

**设备行为：**
1. 收到 `0x18` 后校验 SD 卡已挂载、`update.bin` 存在且大小合法（≤3MB）。
2. 校验通过：发送 `OTAResult(0x00)`（见 §5.17）后**不等待 App 确认收到**，直接重启进入升级流程。升级写入 + 重启预计约 20 秒，期间 BLE 完全关闭，App 发送的任何数据都不会被处理。升级成功后设备再次重启，恢复广播并按 §5.8 发送 `DeviceWake(0x30)`。
3. 校验不通过：发送对应错误状态码（见 §5.17），**不重启**，BLE 连接保持不变，App 可正常收发。
4. 固件收到 `0x18` 后、判定为"已进入升级流程"期间会忽略重复的 `0x18`（防重入）；由于步骤 2 的重启几乎在发送应答后立即发生，App 侧重发实际落入此窗口的概率很低。

**时序图：**

```
   App                                          Device
    │                                              │
    │──── BLE Write 0x18 (无 payload) ──────────→ │
    │                                              │ 校验 update.bin
    │                                              │（SD 卡 / 文件是否存在 / 大小）
    │                                              │
    │←─── BLE Notify 0x18 + 状态码 ─────────────── │
    │                                              │
    │  状态 = 0x00：                              │（不等 App 确认）
    │  ┌──────────────────────┐                   │ 立即重启进入升级
    │  │ 断连（BLE 完全关闭）  │ ←──────────────── │ 写入固件（约 20 秒）
    │  └──────────────────────┘                   │
    │  等待中……                                   │ 升级完成，再次重启
    │                                              │
    │←──── 重新广播 + DeviceWake(0x30) ─────────── │
    │  （恢复正常同步流程）                        │
    │                                              │
    │  状态 ≠ 0x00：                              │
    │  按错误码提示用户，连接不受影响              │（不重启，不断连）
```

**App 侧处理（状态机）：**

```
  idle
   │ 用户在 Settings 触发升级
   ▼
 sending（发送 0x18，等待最多 5 秒）
   │
   ├── 收到非 0x00 应答 ────────────────────────→ failed(deviceRejected)
   │
   ├── 收到 0x00 / 应答到达前先断连 ──→ awaitingReboot
   │                                        │         │
   │                                   收到  │         │ 约 90 秒未收到
   │                                DeviceWake         │ DeviceWake（兜底超时）
   │                                        ▼         ▼
   │                                      idle    failed(timedOutWaitingForReboot)
   │
   └── 5 秒无应答：
         连接仍存活，累计尝试 < 3 次（含首次发送） → 重发 0x18，回到 sending 重新等待
         连接仍存活，累计已尝试 3 次              → failed(noResponse)
         连接已断开（v2.5.21 兜底，见下）        → failed(noResponse)
```

- 发送后进入等待态，最多 5 秒未收到 `OTAResult` 应答**且连接仍存活**时重发；**全程最多尝试 3 次（含首次发送，即最多 2 次重发，约 15 秒）**，仍无应答则判定为发送失败。
- 若应答到达前连接已断开，判定为**大概率已进入升级**（与收到 `0x00` 同等处理），**停止重发**——协议无 ACK/重传层，断连后无连接可发送，继续重发也无意义。**已知局限**：App 无法区分"应答包在无线上丢失、但固件确实已开始升级"与"发送 `0x18` 后恰好因信号丢失等无关原因断连"——两种情况在 App 侧观察到的现象相同（断连、等待、随后收到或收不到 `DeviceWake`），兜底超时（见下）避免误判被无限放大为永久卡死。
- 进入"等待设备回来"态期间：不展示"连接不稳定"等错误提示；靠 §5.8 `DeviceWake(0x30)` 确认升级完成、连接恢复；兜底超时约 90 秒（20 秒预期耗时的 4~5 倍余量），超时未恢复则降级为"连接丢失，请检查设备"提示。
- 进入等待态前快照当前已知固件版本；`DeviceWake` 到达时按 §5.8 的版本字节对比新旧版本给出升级结果（版本变化 / 相同 / 未知，v2.5.19，见下方"已知边界"）。
- 升级触发入口在有效的专注会话进行中时禁用（避免升级导致的断连被误判为专注会话异常中断）；BLE 未连接时同样禁用（v2.5.21——`0x18` 需要活跃连接才能送达，离线点击只会制造悬空的发送态）。
- 「5 秒超时且连接已断开」判 failed(noResponse) 是 v2.5.21 补的兜底出口，覆盖"从未连上就误触发/写入失败被吞/断连回调丢失"的场景——真实的升级重启断连会先走上图「应答到达前先断连 → awaitingReboot」路径（断连回调优先于超时），不会落进这个兜底。

**实现状态（App build 602 修复，2026-07-12）：** App build ≤601 存在实现缺陷：上图「应答到达前先断连 → awaitingReboot」的转移从未生效（内部断连路由标志到 awaitingReboot 才布防，sending 期间断连不会通知状态机），且 5 秒超时在连接已断时不做任何处理。后果：固件按本节设计"发应答后立即重启"时（应答极易与断连一同丢失），App 几乎必然永久停在发送态——界面卡 "Sending..."、按钮不可用，需杀掉 App 恢复；**升级本身不受影响照常完成**，仅 App 侧呈现错误且 DeviceWake 版本对比结果丢失。build 602 起已按本节规格修复。**OTA 联调与验收请使用 App build 602+**；wire 格式与固件侧要求均无变化。

**已知边界（v2.5.19 已关闭）：** 若升级写入或新固件启动失败，设备自动回滚至旧固件并重启——曾经 App 无法区分"升级成功"与"回滚"（两者在 App 侧都表现为断连 → 等待 → 收到 `DeviceWake`）。**v2.5.19 起 `DeviceWake(0x30)` 携带固件版本**（Major.Minor.Patch 各 1B，见 §5.8）：App 在进入等待态前快照当前已知版本，收到 `DeviceWake` 后对比——版本变化 → 升级生效、显示新版本；版本相同 → 提示「设备以相同固件版本回归，更新可能未生效」（注：**回滚**与**staged 了同版本 bin 重刷**在 App 侧仍不可分，均如实按"同版本"提示）；未携带版本（旧固件）→ 按"版本未知"完成流程、不误报失败。

**安全模式：** `BLE_SHARED_SECRET` 已配置时，`0x18` 与其他业务帧一样须封装进 `SecureEnvelope`（`0x7E`，见 §3.4），App 出站侧无需特殊处理（沿用既有 `writeData` 自动封装路径）；**固件侧回复 `OTAResult` 时同样需要封装**，否则会被 App 判定为非法明文包并主动断开连接（见 §5.17）。当前 dev 环境与现有 TestFlight 包均未配置 `BLE_SHARED_SECRET`（明文模式），本节暂按明文联调；正式启用安全模式前，App 与固件需再次确认该封装已双方实现。

**真相源：** 出站字节见 `Core/BLE/BLEProtocol.swift` 的 `BLEDataType.otaReboot`；App 侧状态机见 `BLEOTACoordinator`。

---

### 4.18 WiFiDebugMode (0x19)

App→Device 控制或查询供 PC 联调使用的 Wi-Fi 调试模式。开启后设备启动 SoftAP，PC 连接设备热点后访问 `http://192.168.4.1/`。热点名称、密码及网页服务由固件配置，**不通过 BLE 传输 Wi-Fi 密码**。

**Payload：** 固定 1 字节命令。

| Offset | Field | Size | 值 | 说明 |
|--------|-------|------|----|------|
| 0 | Command | 1 byte | `0x00` | 关闭 Wi-Fi 调试模式 |
| 0 | Command | 1 byte | `0x01` | 开启 Wi-Fi 调试模式 |
| 0 | Command | 1 byte | `0x02` | 查询当前实际状态，不改变设备状态 |

**明文帧示例（App→Device 的 Length 为 2B Big Endian）：**

| 操作 | 完整帧 | 说明 |
|------|--------|------|
| 关闭 | `19 00 01 00` | `Type=0x19, Length=1, Command=0x00` |
| 开启 | `19 00 01 01` | `Type=0x19, Length=1, Command=0x01` |
| 查询 | `19 00 01 02` | `Type=0x19, Length=1, Command=0x02` |

**固件行为：**

1. 每次收到合法的 `0x19` 命令后，都通过 Notify 回一帧 `WiFiDebugResult(0x19)`（见 §5.18）；`Enabled` 必须反映应答时的**实际状态**，而不是 App 请求的目标值。
2. 开启成功后启动 SoftAP 与 PC 调试网页服务，网关固定为 `192.168.4.1`；关闭成功后停止 SoftAP 与调试网页服务。
3. Wi-Fi 调试开启期间必须保持 BLE 可用，继续接收关闭、查询及其他业务命令。**不得因开启 SoftAP 主动断开 BLE**。
4. Wi-Fi 调试状态不持久化；设备每次重启后默认为关闭。App 在 BLE 重连后会重新查询，不会假定重启前状态仍有效。
5. 未知命令值、payload 为空或 payload 长度不等于 1 时，不执行状态变更；若帧仍可识别，应回 `StatusCode=0x04`（非法命令）。

**App 侧处理：**

- App 仅在 BLE 已连接时发送命令；打开 Hardware Details 或 BLE 重连后发送 `Command=0x02` 查询真实状态。
- 开启或关闭时，界面保持“切换中”，收到成功应答后才采用设备返回的 `Enabled`；BLE 写入成功后才开始 5 秒应答计时，超时后保留切换前的已知状态并显示失败。
- 若 `StatusCode=0x00`，但开启命令返回 `Enabled=0x00`、或关闭命令返回 `Enabled=0x01`，App 仍以 `Enabled` 为硬件实际状态，同时显示“命令已接受但状态未切换”的失败提示。
- `StatusCode != 0x00` 时按 §5.18 显示硬件拒绝原因，并以返回的 `Enabled` 校正界面状态。

**安全模式：** `BLE_SHARED_SECRET` 已配置时，`0x19` 与其他业务帧一样封装进 `SecureEnvelope(0x7E)`（见 §3.4），不能发送明文 `0x19`。开启命令的外层帧示意如下；`nonce`、`issuedAt` 与 `HMAC` 必须使用实际值计算，尖括号不是线上字节：

```text
7E 00 31 | 02 19 | <nonce 8B> | <issuedAt 4B> | 00 01 | 01 | <HMAC-SHA256 32B>
^  ^^^^^    ^^^^^                                  ^^^^^   ^
|  外层长度  version + payloadType                  payload  开启命令
外层 Type
```

其中 SecureEnvelope 长度为 49B（`0x0031`），`payloadType=0x19`，内层 payload 仍只有命令字节 `0x01`。关闭与查询只替换最后的命令字节并重新计算签名。上例假设协商后的单次写入长度能容纳整个 52B 外层帧；若不能容纳，App 会按 §3.2 对外层 `0x7E` payload 做通用分包，固件须先重组完整 SecureEnvelope 再验签和解析。

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
| `0x18` | OTAResult           | 固件升级重启应答（1B 状态码，详见 §5.17） |
| `0x19` | WiFiDebugResult     | Wi-Fi 调试模式实时应答（Enabled + StatusCode，详见 §5.18） |
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

> **专注会话期间的用途（v2.5.23）：** 专注态（态 C，设备显示 TaskInPage）进行中，固件应**周期性**发送本帧（建议 ~每 5 分钟一次）以驱动 `FocusStatus(0x14)` 持续更新——这是 **iOS 息屏后台链路的唤醒触发**：iPhone 息屏后系统挂起 App 进程，App 内部的 0x14 定时推送随之冻结（能量瓶子/段位停在息屏那一刻，直到亮屏才补推）。由于专注期间 BLE 连接保持、App 已订阅 Notify 特征，本帧 Notify 会被 iOS 用来**唤醒被挂起的 App**，App 随即现算并回推一帧最新 `0x14`。App 收到 0x20 且有活跃专注会话时，会在 §8.5 的 60s 合并窗**之前**先单独回推 `0x14`（不被 sync 去抖饿死，仅 2s 同内容去重）；整轮 DayPack sync 仍受 60s 合并窗约束。会话结束（CompleteTask/SkipTask）后固件应停止周期发送。周期发送的生命周期**只绑设备本地会话上下文与连接存活**：收到 `0x11 TaskInPage` 建立任务上下文、进入专注页 → 启动；完成/跳过、**连接断开、本地状态丢失或设备重启** → 停止——**不得**用 DayPack(0x10) 偏移 3 的 DeviceMode 字节（设置类快照，App 当前实现恒发 0x00）或其他数据帧字段门控本心跳，专注中收到 DayPack 属正常内容轮换、心跳应继续。断连即会话结束（App 侧同步以 `reason=disconnected` 结束会话），重连后不得凭旧 `0x14`/缓存 DayPack 恢复专注页，应退回概览等待用户重新进入（新 `0x10 EnterTaskIn` → 新 `0x11`）（v2.5.25，§8.7 问题 5）。能量瓶子的「30 分钟递增 / 打断归零」由 App 侧判定并经 0x14 下发、固件无法自算，故此周期唤醒是瓶子在息屏期间按时递增的**必要条件**。

---

### 5.8 DeviceWake (0x30) — 设备上线通知 / Wake Notify

BLE Notify 特征开启后，固件**主动**向 App 发送此帧，表示「设备已上线」。

> **语义澄清**：此帧**不是 App 唤醒 MCU 的命令**，方向是 Device→App。MCU 何时从休眠中醒来由固件自行决定（RTC / 按键 / 电源事件等）。时序：MCU 唤醒 → 广播 → App 扫描连接 → GATT 发现 → 开 Notify → 固件发送此帧。

**Payload：**

| Offset | Field        | Size   | 描述 |
|--------|--------------|--------|-------------------------------|
| 0      | BatteryLevel | 1 byte | 当前电量百分比（App clamp 0-100） |
| 1      | FwMajor      | 1 byte | 固件版本 Major（0-255，v2.5.19 追加） |
| 2      | FwMinor      | 1 byte | 固件版本 Minor（0-255） |
| 3      | FwPatch      | 1 byte | 固件版本 Patch（0-255） |

> **固件版本要求：** `BatteryLevel` 自 v2.3.0+ 必填；**固件版本 3 字节自 v2.5.19+ 必填（整包 payload = 4B，Length = `0x04`）**。版本语义 = 本次启动**实际运行**的固件版本：升级成功后为新版本，升级失败自动回滚后为回滚到的旧版本。App 向后兼容：收到 1B payload（旧固件）时电量正常解析、版本视为未知；空 payload（Length = 0）时忽略电量更新、保持上次已知值。示例：`30 04 64 01 02 03` = 电量 100%、固件 v1.2.3。
>
> **⚠️ 版本字节仅限本实时通知帧：** `0x21 EventLogBatch` 中的 `0x30` 记录**保持 2 字节**（`0x30 + BatteryLevel`，见 §5.15）。批量记录是定长走表解析，在批量记录里追加版本字节会导致 App 解析错位、**整批丢弃**（离线补传丢失）。

**App 响应：**
1. 若 payload 非空：更新并显示设备电量。
2. 若 payload ≥ 4 字节：记录固件版本（Settings 显示；OTA 升级前后对比判定升级结果，见 §4.17）。
3. 同步时间并发送更新数据。

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

**Record 编码：** `eventType (1B) + eventPayload (NB)`，`eventPayload` 按各事件类型定义（见 5.3 ~ 5.17；`0x19` 除外，见下方实时事件约束）。

**解析规则：**
- `0x01~0x06`, `0x20`, `0x31`：无 payload（记录总长 1B）
- `0x30`：`BatteryLevel(1B)`（记录总长 2B，v2.3.0+；**v2.5.19 的固件版本 3 字节不进批量记录**——批量中的 0x30 恒为 2B，追加会错位致整批丢弃）
- `0x18`：`StatusCode(1B)`（记录总长 2B；OTAResult 可作为历史结果进入批次）
- `0x40`：`BatteryLevel`（记录总长 2B）
- `0x16`, `0x17`：`Timestamp(4B)`（记录总长 5B）
- `0x10~0x12`：`Length(1B)+TaskId(NB)+Timestamp(4B)`（记录总长 `2+N+4`）
- `0x13~0x15`：`Length(1B)+Id(NB)`（记录总长 `2+N`）
- `WiFiDebugResult(0x19)` 是连接期实时状态应答，**不属于事件日志，不得出现在本批次**；若混入，App 会按未知记录处理并丢弃整批。
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

### 5.17 OTAResult (0x18)

Device→App，`OTAReboot(0x18)` 的应答事件（方向双义，见 §2.4）。

**Payload：**

| Offset | Field | Size | 描述 |
|--------|-------|------|------|
| 0 | StatusCode | 1 byte | 见下表 |

**状态码：**

| 值 | 名称 | 说明 | 设备行为 |
|----|------|------|----------|
| `0x00` | OK_START_UPGRADE | 升级包检查通过，开始升级 | 发送本应答后立即重启进入升级（不等 App 确认），BLE 关闭约 20 秒 |
| `0x01` | ERR_NO_FILE | 无 `update.bin` | 不重启，连接不变 |
| `0x02` | ERR_FILE_SIZE | 文件大小异常（=0 或 >3MB） | 不重启，连接不变 |
| `0x03` | ERR_SD_CARD | SD 卡未挂载 | 不重启，连接不变 |
| `0x04` | ERR_OTA_FAILED | 升级写入失败 | 不重启，连接不变 |
| `0xFF` | ERR_UNKNOWN | 未知错误 | 不重启，连接不变 |

**App 响应：**
- `StatusCode = 0x00`：转入"等待设备升级完成"态，停止对 `0x18` 的重发，靠 `DeviceWake(0x30)` 确认，详见 §4.17「App 侧处理」的状态机与时序图。
- `StatusCode ≠ 0x00`：按错误码提示用户具体原因（如"请先通过设备 WiFi 上传升级包"），连接不受影响，用户可手动重试。
- **若断连发生在收到本应答之前**（响应包在无线上丢失，但固件实际已经开始升级）：App 判定为大概率成功，处理方式与收到 `0x00` 相同。

**安全模式说明：** `BLE_SHARED_SECRET` 已配置时，App 的 `decodeReceivedMessage`（`BLEService.swift`）对非 `0x7E`/`0x7F` 的入站包一律判定为非法并**主动断开连接**（既有的通用安全行为，非本次新增）。因此固件在安全模式下发送 `OTAResult` **必须**封装进 `SecureEnvelope`（`0x7E`，见 §3.4），否则 App 会拒收并断连，导致这次应答连同"断连即成功"的推断信号一起失效（表现为 App 误判为发送失败或连接故障）。当前明文模式下无此风险。

**真相源：** 入站字节见 `Models/EventLog.swift` 的 `EventLogType.otaResult`；App 侧状态机见 `BLEOTACoordinator`。

---

### 5.18 WiFiDebugResult (0x19)

Device→App，`WiFiDebugMode(0x19)` 的实时应答（方向双义，见 §2.4）。设备应对开启、关闭、查询各回复一次；本事件只表示设备**当前这次连接中的实时状态**。

**Payload：** 固定 2 字节。

| Offset | Field | Size | 说明 |
|--------|-------|------|------|
| 0 | Enabled | 1 byte | 当前实际状态：`0x00=关闭`，`0x01=开启`；其他值非法 |
| 1 | StatusCode | 1 byte | 本次命令处理结果，见下表 |

**状态码：**

| 值 | 名称 | 说明 |
|----|------|------|
| `0x00` | OK | 命令处理成功；`Enabled` 为处理后的实际状态 |
| `0x01` | ERR_UNSUPPORTED | 当前固件或硬件不支持 Wi-Fi 调试模式 |
| `0x02` | ERR_BUSY | 设备正处理其他互斥操作，本次未切换 |
| `0x03` | ERR_WIFI_INIT_FAILED | Wi-Fi / SoftAP 初始化失败 |
| `0x04` | ERR_INVALID_COMMAND | 命令值或 payload 长度非法 |
| `0xFF` | ERR_UNKNOWN | 未知错误 |

`StatusCode != 0x00` 时，`Enabled` 仍必须填写设备应答时的实际状态。例如开启失败、设备仍关闭时返回 `Enabled=0x00`，不能回填请求值 `0x01`。

**明文帧示例（Device→App 的 Length 为 1B）：**

| 结果 | 完整帧 | 说明 |
|------|--------|------|
| 开启成功 | `19 02 01 00` | `Enabled=0x01, StatusCode=0x00` |
| 关闭 / 查询为关闭 | `19 02 00 00` | `Enabled=0x00, StatusCode=0x00` |
| 开启失败 | `19 02 00 03` | 实际仍关闭，Wi-Fi 初始化失败 |

**实时事件约束：** `WiFiDebugResult` 只通过当前 BLE 连接的 Notify characteristic 实时发送，**不得写入、排队或重放到 `EventLogBatch(0x21)`**。原因是 Wi-Fi 调试状态在重启后自动关闭，离线回放旧应答会把 App 界面改成过期状态；App 对未知或过期连接上的应答可忽略。

**安全模式：** 安全模式下设备回复也必须封装进 `SecureEnvelope(0x7E)`，不能发送明文 `0x19`，否则 App 会按通用安全规则拒收并断开连接。开启成功应答的外层帧示意如下：

```text
7E 32 | 02 19 | <nonce 8B> | <issuedAt 4B> | 00 02 | 01 00 | <HMAC-SHA256 32B>
^  ^^    ^^^^^                                  ^^^^^   ^^^^^
|  外层长度  version + payloadType              payload  Enabled + StatusCode
外层 Type
```

Device→App 外层 Length 为 1B；SecureEnvelope 长度为 50B（`0x32`），内层 `payloadType=0x19`、`payloadLen=0x0002`。签名规则、时间窗口与 nonce 防重放要求同 §3.4。上例假设 Notify 能容纳整个 52B 外层帧；若协商 MTU 不足，设备须按 §3.2 对外层 `0x7E` payload 分包，App 重组完成后再解封。

---

## 6. 页面数据结构

> **v2.5.0 重写**：设备 UI 是「常驻框架 + 可换数据面板」，不再是「4 页各说一句」。旧 §6.1–6.4（每页一句宠物文案）已废弃，论证见 §6.5。（编号 §6.4 自 v2.5.30 起由「每日总结面板」复用，与旧废弃内容无关。）

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

> **v2.5.30 布局拍板（客户《电子墨水屏需求》2026-07-20）**：原「进度条 vs 任务清单」开放问题关闭——概览（进行中日程）页按**相邻日程间隔**二分：**前一日程 `EndTime` 到下一日程 `Time` 间隔 <10 分钟 → 情况一**（当日完成比例进度条 `TasksCompleted/TasksTotal` + 事件卡）；**≥10 分钟 → 情况二**（下一日程事件卡 + 任务清单 `TopTasks[]`；**恰好 10 分钟归情况二**，客户确认默认口径 2026-07-20）。判定在固件本地做（App 两组数据都发，`EndTime` 自 v2.5.30 起在 wire 上）。

---

### 6.3 专注详情面板

用户在设备上选中任务进入专注时显示：

- 任务标题 + 描述 + Tips（鼓励）
- 能量瓶

**数据来源：** `0x11 TaskInPage`（由设备 `0x10 EnterTaskIn` 触发）+ `0x14 FocusStatus`（专注状态与能量瓶实时推送）。**不在 DayPack 内。**

---

### 6.4 每日总结面板（v2.5.30，客户「页面四」）

用户在「进行中日程」页**长按按钮「完成当日」**进入；误触保护：**再次长按返回**进行中日程页。触发与页面流转是**固件本地行为**（同 §6.7 状态机原则），**无新增入站字节**——硬件进入本页可用既有 `RequestRefresh(0x20)` 请求 App 拉新（受 §8.5 合并窗约束，显示的始终是最近一轮 sync 推送的文本）。

内容两段（自上而下；客户 2026-07-20 确认"分3部分"系笔误、实为两部分，v2.5.31）：

1. **概况点评** = DayPack.`SettlementReview`（≤180B，中性面板口吻）。App 生成硬规则：今日含 `Category=0x04` 死线类日程必提该日程；当日专注累计 >2h 必提专注时长；其余 AI 自由发挥。v2.5.31 起为**输出侧校验**——AI 文本不满足硬规则即回退恒满足的确定性兜底模板。
2. **金句 / 明日鼓励** = DayPack.`SettlementQuote`（≤120B，换行显示）。三分支（App 判定）：日程+任务全部完成**且当日无未结束日程** → IP 人格庆祝式收尾；未全部完成且「今日日程时长（重叠区间合并计）+ 专注时长」>4h → IP 风格表达「今天已很努力，只是任务定多了，明天可减量、从稳定完成开始」；否则（含恰好 4h）→ 客户指定固定文案（"When the schedule is full, plan fewer tasks to leave room for focus."）。

数值区（进度比例等）继续复用 `SettlementData` 定长字段（§4.7）。

> 决策记录：两段文案由 App 生成随 DayPack 预推、而非硬件长按时实时请求——BLE 断连是常态（§6.7 同一论证），总结页必须离线可显示；代价是文本最多滞后一个 `0x20` 合并窗（~1 分钟），产品可接受。v2.5.30 曾按 mock 推断第三段「明日预告」（`TomorrowFirstUp`），客户确认为笔误后 v2.5.31 撤除。

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
| 每日总结·概况点评 | **SettlementReview（v2.5.30 新增，≤180B）** | 旧 settlement 双消息 v2.5.0 已删；现按客户规则重生（死线/专注硬规则），见 §6.4 |
| 每日总结·金句/明日鼓励 | **SettlementQuote（v2.5.30 新增，≤120B）** | 新增（三分支），见 §6.4。（v2.5.30 的 TomorrowFirstUp 已于 v2.5.31 撤除） |
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
- ⚠️ 待与固件定稿的边界值：晚间倾向结算展示的起始时段。「进行中事件」的持续窗口自 v2.5.30 起可直接用 `Events[].EndTime` 判定（当前时刻落在 `Time`~`EndTime` 内 = 进行中），不再需要"下一事件开始前"的近似。

---

## 7. 示例数据

### 7.1 DayPack 最小测试向量（Hex）

> ⚠️ **下方 hex 向量是 pre-v2.5.0 旧布局，已废弃，切勿照其实现解析（v2.5.9）。** 它含 `MorningGreeting / DailySummary / FirstItem / CurrentScheduleSummary / CompanionPhrase` 及结算双消息——这些字段 v2.5.0 已删除，与现行 §4.7 完全不符。手工维护逐字节向量会随协议演进错位、反误导固件，故不再在此给出新向量，改为下面的**当前字段顺序** + 指向 App 侧锁步维护的**权威往返自检**。
>
> **当前 DayPack(0x10) payload 字段顺序**（详见 §4.7；变长字符串 = 1 字节长度 + UTF-8 内容，长度为 0 的空串也占 1 字节、必须照样消费再前进）：
> `Year(1) Month(1) Day(1) DeviceMode(1) FocusChallengeEnabled(1) PetDialogue(1+N) EventCount(1) Events[]{Time(1+N) Title(1+N) Description(1+N) Category(1) EndTime(1+N)}×N TaskCount(1) TopTasks[]{TaskId(1+N) Title(1+N) IsCompleted(1) Priority(1)}×N SettlementData(10B 定长) DaySummary(1+N) FirstUp(1+N) SettlementReview(1+N) SettlementQuote(1+N，最后一个字段)`。读完 `SettlementQuote`，解析指针应恰好停在 payload 末尾。（`Category` 为 v2.5.27 的每事件 1 字节类别，见 §4.7 六大类映射表；`EndTime` 与两个结算尾字段为 v2.5.30/v2.5.31，见 §4.7。）
>
> **权威自检（推荐固件对照）**：App 侧 `BLEProtocolSimulationSupport.swift::parseDayPack()` 按上序逐字段读回并 `requireEnd()`（任何尾部多余字节即报错），与 `BLEDataEncoder.encodeDayPack` 在 `BLEProtocolSimulationTests` 做往返断言；编解码**锁步维护**，是当前布局的权威字节级参考。固件实现解析器后，可请 App 侧据此导出一条与现行布局一致的具体 hex 向量。

以下 hex 块是 **pre-v2.5.0 旧布局的历史样例，切勿照其字段实现**（见上方废弃横幅）；保留仅为演示两类最易错位的长度前缀陷阱（`★` 处）。当前布局请按上面的**当前字段顺序** + App 侧仿真往返自检对照。左侧 `@N` 为该字段在 **payload 内的起始字节偏移**（十进制）——注意偏移随变长字符串累积，**不是固定值**。

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

**（历史样例的原自检口径，仅供理解长度前缀机制，勿按其字段实现）**：旧布局解析后应得到 `MorningGreeting="Hi"` 等旧字段值且指针恰好停在第 58 字节。**当前布局的自检以「当前字段顺序」+ `BLEProtocolSimulationTests` 往返断言为准。**

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
| 分包总数超过 65535 | 丢弃（v2.5.24 前上限为 255） |
| 固件→App 分包消息需重传（含发送停顿 >5 分钟后恢复） | **从 `Seq=0` 重发整条消息**——App 侧 5 分钟闲置超时 + 丢弃名单会忽略中途续传的 `Seq>0` 尾片，`Seq=0` 才能解除丢弃标记并重新建槽（§3.2 App 侧重组生命周期，v2.5.26） |
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
| RequestRefresh sync 触发最小间隔（合并窗） | **60 秒（联调期）**，**仅** RequestRefresh(`0x20`) 触发的整轮 sync 适用。使用**独立**闸，不消耗 DeviceWake 的 10 秒配额、也不会被频繁 DeviceWake 饿死。**联调期固件把 0x20 当 ~2s 心跳狂发**，60 秒合并窗把 30 次/分的背靠背 sync 去抖为 ≤1 次/分（窗内重复被合并并记录日志）；固件停止心跳化后可回调更短值、用户按键即时触发。（历史：曾短暂**硬抑制** 0x20，连带停掉用户物理刷新；v2.5.14 改为去抖合并、恢复用户刷新。）**专注例外（v2.5.23）：** 有活跃专注会话时，0x20 触发的 `0x14` 单帧回推在本 60s 合并窗**之前**发出、不被去抖（仅 2s 同内容去重约束）；只有整轮 DayPack sync 仍受合并窗约束——保证息屏期间瓶子/段位按时更新，见 §5.7。心跳启停只绑设备本地会话事件与连接存活，**不受 DayPack(0x10) 内 DeviceMode 字节门控**（v2.5.25，§8.7 问题 5）。|

**调试建议**：若发现 App 长时间无响应或未按预期刷新，可检查是否触发了限流——`0x20` 触发的整轮 sync 在 **60 秒合并窗**内被去抖（联调期，防固件把 0x20 当心跳刷屏）、`0x30` 在 10 秒内重复触发整轮 sync 会被忽略（两者互不占用配额），或写入频率超过 20 次/秒被排队。

**帧可见性（联调）**：DEBUG 包与 TestFlight 包可用 Console.app 过滤 `subsystem:com.kirole.app category:BLE` 查看 App 收发帧摘要——TX 记录 `type/len`、RX 记录 `len/firstByte`；正式 App Store 包关闭，且不记录完整 payload。

**同步回路：Time(0x05)→RequestRefresh(0x20) 反射与 DayPack 双发（2026-07-03 联调）**

联调实测：固件每收到 `Time(0x05)` 即回一个 `RequestRefresh(0x20)`（固件日志 `RTC synced → Triggering RequestRefresh`）。而 Time 是 App **每轮 sync 的第一帧**——"收到同步的开头就请求新同步"构成自激回路：该 0x20 到达时本轮 sync 尚在途，App 会在收尾后补跑一轮 force sync；若两轮之间恰有内容变化（典型：LLM 对话文本在 ~3 秒内生成完成），第二轮真发 DayPack——硬件 3 秒内收到 MsgID 连号、除 PetDialogue 外完全相同的两个 DayPack，背靠背双刷屏。首次连接与任务/日程变更后最易复现（这两种场景对话必然重新生成）；对话缓存命中时两轮内容一致、第二轮不发 DayPack，现象即"消失"。

- **App 侧已修（build 589）**：sync 组包前等待在途的对话生成完成（首轮即携带最终文本）；此后反射补跑轮因指纹无变化**不再携带 DayPack**，退化为 Time/PetStatus 小帧，不触发刷屏。
- **固件侧建议**：
  1. 收到 `Time(0x05)` **不要**触发 `RequestRefresh(0x20)`。0x20 保留三种意图：开机/唤醒后久无数据、用户物理按键刷新、**专注会话进行中的周期性刷新（~5 分钟/次，驱动 `0x14` 息屏后台更新，见 §5.7）**。除专注周期刷新外，App 每轮 sync 都会主动推送全量数据，无需设备回请。
  2. E-ink 渲染进行中（7.3 寸全刷 ~12s）收到新 DayPack 时，**合并到下一次刷新**（只保留最新一包），不要排队逐包刷屏。

### 8.6 设备信任模型（TOFU）

App 采用 **首次连接即信任（Trust On First Use）** 策略：

- 首次连接成功的设备 UUID 会被永久记录为"受信任设备"
- 后续扫描时，若已有受信任设备，**其他未知设备会被直接过滤**，不会出现在扫描结果中
- 如需连接新的测试设备，须先在 App 设置中清除已记录的设备信任记录

**联调注意**：更换测试硬件时，如果 App 扫描不到新设备，通常是此机制导致，清除信任记录后重新扫描即可。

### 8.7 联调实测：固件实现偏差（2026-05-29 `ble_log` · 2026-07-04 增补）

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

**问题 4：EnterTaskIn(0x10) payload 未按 §5.3 实现（2026-07-04 联调实测，build 591）**

设备滚轮选择任务进入详情时，实测发出 `10 08 00 00 00 00 31 fa 77 5c`——payload 仅 8 字节、首字节 `0x00`，疑似自创的「idx(4B)+Timestamp(4B)」布局（固件日志亦打印 `task idx=0`）。§5.3 要求 `Length(1B) + TaskId UUID字符串(N字节) + Timestamp(4B BE)`。App 按协议解析得到**空 taskId** + 错位读出 ~1970 时间戳，因此：**不回发 0x11 TaskInPage**（找不到任务，正确拒绝），并回发 `DeviceMode(0x12)=Interactive` 作为解卡信号——本次实测设备收到了该帧但**未退回概览页**，请固件实现「收到 0x12=Interactive 且处于任务详情/专注页时退回概览」的解卡协作。

正确示例（以实测任务为例）：UUID `5A81C920-4199-4B73-A76B-F54496CAC272` 应发 payload = `0x24`(=36) + 36 字节 UUID ASCII + 4 字节时间戳，共 41 字节。**WheelSelect(0x14) 中该 UUID 发送正确**——把同一 UUID 放入 EnterTaskIn 即可；CompleteTask(§5.4)/SkipTask(§5.5) 为同一格式，请一并自查。App 侧已加防御（build 593 起：空/未知 taskId 不再开专注会话，不再出现 `task="Unknown Task" elapsed=65535 bottles=255` 的 0x14 帧）。

另记 App 侧**专注显示推送合流**（build 592 起，wire 不变）：聚焦结束仅 `0x14(idle)` 立即发送、`0x17` 仅在新场景解锁时发送、内容更新由随后的 DayPack 轮承载；同内容 0x14 短窗（2 秒）去重——设备侧「完成聚焦任务连刷三次」现象随之消失。

**问题 5：DayPack 的 DeviceMode 字节被误用于门控 §5.7 专注周期唤醒（2026-07-14 联调实测）**

专注会话进行中（App 刚推 `0x14 FocusStatus phase=1 elapsed=2min task="task03"`），一轮例行 sync 的 DayPack(0x10) 送达，固件解析出 `DeviceMode: Interactive` 后随即打印 `Focus refresh heartbeat disabled (300s interval)`——§5.7 的专注周期唤醒（~5 分钟一次 0x20）被关闭。后果：v2.5.23 修复的「息屏后能量瓶子不按 30 分钟递增」在**息屏/App 被挂起区间**复发（前台期间 App 自身的推送循环仍在推 0x14，故现象集中在息屏后）——0x20 周期唤醒正是息屏链路唯一可靠的唤醒通道。

固件需对照修正两点：

1. **DayPack 偏移 3 的 DeviceMode 不是专注态信号。** 它是设置类快照字段，App **当前实现恒发 `0x00`**（Interactive，进不进专注都不变；`0x01=Focus` 仍是合法 wire 值、保留不废），且专注态本就「不在此包内」（§4.7 开头原文，专注由 `0x11`+`0x14` 驱动）。据它判定「是否在专注」永远得到「否」，心跳被恒假信号关死。
2. **§5.7 周期唤醒的生命周期只绑设备本地会话上下文与连接**：收到 `0x11 TaskInPage` 建立任务上下文、进入专注页 → 启动；发出 CompleteTask/SkipTask、**连接断开、本地状态丢失或设备重启** → 停止。专注进行中的实时进度权威是 `0x14 FocusStatus`（Phase `1=warmup/2=building/3=deep` 为活跃、`0=idle`，按当前未打断段计），态 C 的建立与退出由 `0x11` + 本地会话事件驱动——**不得**用 DayPack 的任何字段改变专注页状态或心跳。

配套边界（照做可避免次生 bug）：
- **专注中收到 DayPack 属正常**（任务变更/内容轮换都会触发整轮 sync）：仅作后台缓冲，不驱动任何态切换、不动心跳；
- **断连即会话结束**：App 在 BLE 断开时立即结束专注会话（`reason=disconnected`），重连后**不存在可恢复的旧会话**——不得凭缓存 DayPack 或旧 `0x14` 复活态 C，应退回概览、等待用户重新进入（新 `0x10 EnterTaskIn` → 新 `0x11`）；
- **退出专注后**：概览以随后新一轮 DayPack 为准（App 在会话结束时主动请求一轮同步），专注期间的旧缓存最多短暂占位。

（与 `0x12 DeviceMode=Interactive` 解卡信号的区分：`0x12` 是 App 主动下发的**指令帧**，仅在异常解卡场景发送、要求设备退回概览——见问题 4；DayPack 内的同名字节只是随包携带的快照，两者语义不同，不可混用。）

验收用例（固件自查）：① 专注中收到 DayPack → 心跳继续、专注页不退出；② 专注中断连→重连 → 设备退回概览，不凭旧数据复活专注页；③ CompleteTask 退出后 → 等待并采用新一轮 DayPack 刷新概览。

---

## 9. 专注时间计算

### 9.1 概述

专注时间通过结合设备事件与手机屏幕活动数据来计算。目标是测量任务会话期间的实际专注工作时间。

### 9.2 数据来源

| 来源 | 数据 | 用途 |
|--------|------|---------|
| 设备事件 | EnterTaskIn、CompleteTask、SkipTask 时间戳 | 定义任务会话边界 |
| Screen Time API（DeviceActivity） | 用户自选分心 App 的使用事件 | 检测会话期间的分心打断（v2.5.20：判定源由「手机解锁/Kirole 回前台」更正为「使用自选分心 App」） |

### 9.3 计算算法

```
Focus Session:
  Start: EnterTaskIn timestamp
  End: CompleteTask or SkipTask timestamp
  Duration: End - Start

Focus Time Calculation:
  1. Get all interruption events during the session
     (v2.5.20: interruption = usage of the user's self-selected distracting apps)
  2. For each 30-minute window without interruption:
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

- 使用 `DeviceActivityMonitor` 框架监测**用户自选分心 App** 的使用（清单复用深度专注的应用选择）
- 需要用户授权 Screen Time 访问权限
- 未授权 / 未选分心 App / 监测扩展未上线时：App **不记打断**（无打断检测），并在专注界面明示；不回退到任何近似信号（v2.5.20）
- 本地存储专注会话数据以支持离线计算
- 连接时将专注数据同步至云端
- 离线回放事件只保证任务完成状态能补记；离线期间的专注时间不保证完整计算，因为 App 没有当时的手机解锁数据。
- 回放补记任务完成时只应用状态变更（任务状态、宠物积分、持久化、外部同步），不触发实时反馈（声音/震动/完成俳句）——这些只属于实时用户操作（v2.5.2）。

---

## 10. Spectra 6 像素数据格式

> **注意：** 屏幕硬件规格（分辨率、色彩技术）的权威来源为 `硬件需求文档-Hardware-Requirements-Document.md` Section 4。本节仅描述像素数据在 BLE 传输中的编码格式。
>
> **v2.5.24 起 `CustomAvatarFrame(0x15)` 不再使用本节 4bpp 编码**——头像帧改传 PNG（§4.12），Spectra-6 量化 / 抖动改由固件在渲染时完成，App 侧已移除全部 4bpp 打包代码。本节保留用于固件内部帧缓冲格式约定与未来可能的整屏图传命令；当前 wire 上**没有任何命令**携带 4bpp 载荷。

### 10.1 概述

E-ink 显示屏使用 E Ink Spectra 6 技术，支持 6 种颜色。像素数据采用 4bpp（每像素 4 位）格式编码，每字节打包 2 个像素。

本节仅保留像素编码定义。当前 iOS App 没有携带 4bpp 载荷的业务命令（头像帧 `0x15` 自 v2.5.24 起为 PNG，见 §4.12），固件无需实现 4bpp 帧接收。

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
    case customAvatarFrame = 0x15  // App→Device: 自定义伴侣头像 PNG（SubVersion 0x02，见 §4.12）
    case screensaver = 0x16        // App→Device: 屏保金句/明信片业务帧（替代旧 0xAA 01 02，见 §4.15）
    case sceneUnlock = 0x17        // App→Device: 场景解锁业务帧（替代旧 0xAA 01 01，见 §4.16）
    case otaReboot = 0x18          // App→Device: 触发固件升级重启（零 payload），见 §4.17
    case wifiDebugMode = 0x19      // App→Device: 开启/关闭/查询 PC Wi-Fi 调试模式，见 §4.18
    case eventLogRequest = 0x20
    case eventLogBatch = 0x21
    case secureData = 0x7E
    case securityHandshake = 0x7F
}
```

`WiFiDebugResult(0x19)` 由实时 BLE 通知处理，不加入 `EventLogType`，也不进入 `EventLogBatch(0x21)`。

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
    case otaResult = "ota_result"  // 0x18，见 §5.17
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

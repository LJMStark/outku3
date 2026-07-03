---
name: ble-wire-change-control
description: BLE wire 字节格式变更的强制流程（BLEDataEncoder 的 encodeDayPack/encodeWeather、新帧字节、字段增删、字节预算 DayPackTextBudget），含镜像解码器 requireEnd/trailingBytes 同步铁律。改任何上线字节前必读。NOT for 联调期行为问题（去 ble-sync-runbook）或纯文档措辞修订（去 docs-contract-change-control）。
---

# BLE Wire 变更管控

## 适用

- 给 `BLEDataEncoder` 的任何 `encode*` 增删字段、改字段顺序、改长度前缀
- 新增/退役帧类型字节（`BLEProtocol.swift` 的 `BLEDataType` / `EventLog.swift` 的 `EventLogType`）
- 调整文本字节预算（`DayPackTextBudget`）
- 改分包、安全信封、CRC 等传输层结构

## 不适用（先别用这份）

- 硬件收到了数据但行为不对 / 不刷新 → `ble-sync-runbook`
- 协议文档只改措辞、示例、章节引用，不动字节 → `docs-contract-change-control`
- 判断某个字节行为"是不是 bug" → `intentional-behaviors-contract`

## 铁律 1：镜像解码器必须同步，且空字符串也算字节

测试层有一个**严格镜像解码器**：`BLEProtocolSimulationSupport.swift` 的 `parseDayPack` / `parseWeather`
逐字节重放 wire 并在结尾调 `requireEnd()`——任何没被读走的尾字节直接抛 `trailingBytes`。

- 给 `encodeDayPack` 加字段 → 必须在对应 `parse*` 的 `requireEnd()` **之前**读回它，
  并更新 fixture + `Simulated*` 结构 + round-trip 断言。
- **空的长度前缀字符串也追加 1 字节**，一样会炸。
- `BLEProtocolTests` 是手工走游标的，**不会**发现 desync——必须跑全量 `swift test`
  （包含 `BLEProtocolSimulationTests`），不能只跑 `BLEProtocolTests`。
- 补课案例：`fb823e1`（DaySummary 字段加了、解码器忘了，事后补）。这类补课 commit 不该再出现。

## 铁律 2：字节预算单一真源

所有 DayPack 文本字段的字节上限在 `BLEDataEncoder.swift:9` 的 `DayPackTextBudget`（`8122b7f` 收敛）。
改预算值时：

1. 只改这一处，别在调用点写数字；
2. 同步 `docs/BLE通信协议规格文档.md` 对应 § 的上限标注（固件按文档分配缓冲区）；
3. LLM 输出侧预算与 wire 预算的关系见 `llm-prompt-safety-contract`。

## 铁律 3：出站文本恒为可打印 ASCII

`appendString` 是**单点净化口**：所有出站字符串经 `StringASCIIWireSanitizer` 转成 `0x20–0x7E`
（v2.5.14，`c4a2b4e`）。LLM 弯引号/长破折号、用户 emoji、日历 CJK 都会被转写或丢弃——硬件字库只认 ASCII。

- 新增文本字段**必须**走 `appendString`，不得手拼 `Data`；
- "emoji 被静默丢弃"是有意行为，别当 bug 修（见 `intentional-behaviors-contract`）；
- 有虚拟硬件级测试守着（`f4c45c5`、`ab6f2fa`），改净化逻辑前先读这两个测试。

## 铁律 4：字节命名空间按方向分裂

出站字节定义在 `Core/BLE/BLEProtocol.swift`，入站在 `Models/EventLog.swift`。**同一个字节值两个方向
可以是两种意思**——`0x15` 出站是 CustomAvatarFrame、入站是 ViewEventDetail。这是刻意设计
（`221d44e` 有专门结论 commit："no byte change needed"）。

- 新增帧字节时只需在**本方向**命名空间内查重；
- 但要在协议文档的两张字节表里都确认清楚归属，`0x21 eventLogBatch` 挂在 `BLEDataType` enum 里
  纯属命名空间归类，实际方向是入站——别被 enum 位置骗了。

## 铁律 5：格式化输出钉死 locale

进 wire 的时间字符串必须用 `en_US_POSIX` formatter（`2ad9ca1` 修过 Event/TaskSummary 的 HH:mm）。
用户设备的 12/24 小时制、区域设置**不能**影响 wire 字节。同理，DayPack 指纹的组成部分要转义分隔符
（`095f28f`）且与 locale 无关（`bf1c057`）。

## 变更清单（全部完成才算改完）

1. `encode*` 与镜像 `parse*` 同步，fixture / round-trip 更新
2. 全量 `cd KirolePackage && swift test` 绿（不是 filter 跑）
3. `docs/BLE通信协议规格文档.md` 版本号递增 + 修订历史表新行 + 受影响 § 更新 → 走 `docs-contract-change-control`（含飞书同步）
4. 若字段影响 DayPack 指纹（决定要不要推硬件），确认指纹只含**上 wire** 的内容——off-wire 数据混入指纹
   会造成无意义重推（教训：`4603d3a` 把不上 wire 的结算语挤进过指纹）
5. 前向兼容评估：新字段追加在帧尾 = 旧固件可忽略（如 SegmentMinutes `7f2869d` 的做法：追加而非重定义
   现有字段语义——v2.5.4 曾想重定义 ElapsedTime，v2.5.5 撤回改为追加新字段，这是本仓库的兼容范式）

## 姊妹文档

- `docs-contract-change-control` — 第 3 步的文档/飞书细则
- `ble-sync-runbook` — 改完后硬件行为不对时
- `intentional-behaviors-contract` — 0x15 复用、Mood 通道、ASCII 丢弃等"别修"清单
- `failure-archaeology` — 镜像 desync、指纹污染的完整事故记录

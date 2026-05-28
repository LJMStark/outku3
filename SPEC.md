# Kirole vs Inku 对标改进规范

> 制定日期：2026/05/28
> 状态：已批准，按 P0 → P1 → P2 → P3 顺序执行
> 来源：与竞品 Inku（E-ink 日历 + AI 陪伴）三方交叉验证调研 + 用户逐项访谈

---

## Context（背景）

Kirole 是 E-ink 硬件优先的宠物陪伴产品。本规范源于一次与竞品 Inku 的对比调研：

- 原 7 点对比里 4 点 Kirole 已实现（乐观 UI、自定义头像管线、Roast Mode、Apple Calendar）
- Inku 2025/12 上线 "Big Refresh"，把原"它独有"的 5 个点也补齐（视频会议链接、时区检测、Apple Reminders、Avatar Library、What's New）
- 三个独立 agent（code-explorer / general-purpose / architect）交叉验证挖出 12 个新缺口，多 agent 撞同一处的项目可信度最高
- 行业证据（Friend.com 翻车 / Replika 被罚 / Kindroid 47 参数 / Daylight DC-1 软件停滞教训）反向修正了原对比中的若干结论

整套规范的目标是把"对标焦虑"转换为基于事实的执行清单。

---

## 用户产品哲学（贯穿所有决策）

**愿意投资**：基础设施 + 护城河
- 数据正确性（事件回放幂等、LLM 输出字节防线）
- 用户主动操作的诚实反馈（远端 sync Toast、BLE 分层即时推、Custom 推送重试）
- IP 一致性（fallback 按 CompanionStyle 切分）
- 长期护城河（CustomCompanion 走 Kindroid 路线）
- 协议层基础（BLE full_refresh 帧）

**不愿投资**：装饰 + 后台被动状态
- 让 App 反映硬件被动状态（hardware offline 文案降级）
- 给所有用户加新设置项（AI 风格档位、What's New）
- 后端复杂度高、收益边际的项（Silent Push 兜底）

**核心边界**：**App 是 App，硬件是硬件，不强行联动**。但用户主动操作必须有诚实反馈，无论操作是否成功送达硬件 / 远端。

---

## 优先级清单

### P0 — 基础设施（必做）

| 项目 | 主要文件 | 工作量 |
|---|---|---|
| eventLogBatch 幂等保护 | `Core/Services/BLEEventHandler.swift:261-285` | 0.5d |
| LLM 输出字节硬截断 + fallback | `Core/Network/CompanionTextService.swift`、`OpenAIService.swift:336-357` | 0.5d |
| BLE 分层推送（前台即时 + 后台节流） | `Core/BLE/BLESyncCoordinator.swift`、`Models/AppState+Actions.swift`、`AppState+CustomCompanions.swift` | 1d |
| 远端 sync 失败 Toast + Settings 徽章 | `Models/AppState+Sync.swift:113-114`、`AppState.swift` 新增 `syncErrors`、`Views/Settings/` | 1d |

#### P0-1：eventLogBatch 幂等保护
- **现状**：`BLEEventHandler.applyEventStateMutation.completeTask` 直接调 `toggleTaskCompletion`，不检查当前状态。硬件离线时点完成 → App 也手动点完成 → 硬件回放 → 任务被 toggle 回未完成（数据破坏）
- **决策**：加 `(EventLog.id, eventType)` 幂等表 + 按 `log.timestamp` 排序后依次 apply
- **依据**：CustomCompanion Kindroid 路线的跨会话记忆层（Future Backlog）也依赖这个幂等保证

#### P0-2：LLM 输出字节硬截断 + fallback
- **现状**：companionPhrase / taskEncouragement / CustomCompanion 路径都依赖 LLM 自觉控制长度（prompt 软约束）。LLM 偶发返回 40 词长句到 E-ink 上会乱码
- **决策**：`CompanionTextService.generateAIText` 出口加 `enforceByteBudget(text, maxBytes: 120)`，超限 trim 到最后一个句号；连续超限 fallback 到 FallbackText

#### P0-3：BLE 分层推送
- **现状**：`BLESyncCoordinator.performSync(force:)` 参数已存在，但 `AppState+Actions.swift` 的 addTask / completeTask 后没触发 `force: true`，用户改任务要等下个节流窗口（最长 1h）才上硬件
- **决策**：走 Apple Watch / Pebble 最佳实践——前台用户主动操作（addTask、editTask、deleteTask、completeTask、切宠物、Custom Companion 更新）→ 立即 `performSync(force: true)`；后台 / 时间驱动 → 仍走节流
- **依据**：BLE 单次推送电量代价远小于持续连接保持；iOS 前台不受后台 BLE 限制约束
- **连锁影响**：`0x10 enterTaskIn`、`0x21 eventLogBatch` 等 BLE 帧设计要支持"小帧高频"模式

#### P0-4：远端 sync 失败 Toast + 徽章
- **现状**：`syncGoogleData / syncNotionData / syncTaskadeData` 失败时只调 `ErrorReporter.log()`，用户完全无感知。点 Sync now 后用户以为成功但实际不是
- **决策**：Toast "<Provider> sync failed, tap to retry" + AppState 加 `syncErrors: [provider: error]`，Settings 远端同步项显示错误状态徽章
- **注意**：这与"App 不反映硬件状态"哲学不冲突——用户主动操作后的反馈是另一回事

---

### P1 — 基础设施完善 + 护城河起步（推荐做）

| 项目 | 主要文件 | 工作量 |
|---|---|---|
| Fallback 按 CompanionStyle 切分 | `Core/Network/FallbackText.swift`、`CompanionTextService.swift` | 1d |
| CustomCompanion BLE 推送失败入队 + 重连 flush | `Models/AppState+CustomCompanions.swift:142-150`、`LocalStorage.swift`、`BLEService.swift` | 1d |
| Roast Mode 默认关 + 首次开启教育 | `Models/CustomCompanion.swift:12`、`CreateCustomCompanionSheet`、`OpenAIService.swift:296` | 0.5d |
| CustomCompanion Kindroid 第一步（5-8 维度 + backstory） | `Models/CustomCompanion.swift`、`CreateCustomCompanionSheet`、`OpenAIService.swift` 的 `customCompanionPersonaPrompt` | 2-3d |

#### P1-1：Fallback IP 切分
- **现状**：`FallbackText.swift` 是通用英文话术，Silas（圣经意象）用户离线时收到通用 "You've got this!"，IP 一致性破；Custom Companion 离线连身份都丢
- **决策**：按 `CompanionStyle` 切分。joy/silas/nova 各一套 8-12 条 ≤15 词预制句；Custom Companion 用其 `personaVoice` 拼装，未来 Kindroid 引入 backstory 后用 backstory 提取关键词补充

#### P1-2：CustomCompanion BLE 推送重试
- **现状**：`pushCustomAvatarFrame()` 是 best-effort 一次性推送，失败仅打日志。BLE 重连后不会自动补传，直到下次用户切换伴侣
- **决策**：push 失败入队（`LocalStorage.pendingCustomCompanionPush`），BLE 重连时（`BLEService.connectionState == .connected`）自动 flush；硬件渲染未上线期间 UI 明示"硬件将显示默认 IP"
- **组合策略**：与 P0-3 BLE 分层组合 → **前台即时推 + 失败入队 + 重连 flush 三步保证**

#### P1-3：Roast Mode 默认关 + 教育
- **现状**：`CustomCompanion.roastModeEnabled` 已实现且默认开
- **决策**：保留字段，**默认关闭**。用户首次主动开启时弹"Your companion will tease your habits, you can turn it off anytime"
- **依据**：Friend.com AI 项链因嘲讽翻车被迫"lobotomize"角色；Inku 没做模式只做行为。**Kindroid 路线下 P1-4 会用"敏感话题边界"维度替代/升级 boolean toggle**

#### P1-4：CustomCompanion Kindroid 第一步
- **现状**：CustomCompanion 只有名字、照片、roastModeEnabled、几个 personaVoice 关键词
- **决策**：扩展到 5-8 个核心维度：
  - 性格基调（preset 选项）
  - 说话方式（preset 选项；可吸收"叙事 / 简练 / 俳句"三档作为 preset）
  - 关系定位（朋友 / 导师 / 伙伴 / 其他）
  - 好奇心滑杆
  - 幽默度滑杆
  - 严格度滑杆
  - backstory 自由文本框
  - 敏感话题边界（自由文本，替代 Roast Mode boolean toggle）
- **依据**：足以拉开和 Inku Avatar Library 的距离，但不到 Kindroid 47 参数那种创建门槛
- **意义**：CustomCompanion 从"周边小功能"升级为"护城河之一"

---

### P2 — 用户功能（关键日历基础）

| 项目 | 主要文件 | 工作量 |
|---|---|---|
| 时区变化 Toast + 一键调整 | `Core/Storage/LocalStorage.swift`、新增 `Core/Services/TimezoneObserver.swift` | 0.5d |
| 视频会议链接检测 + Join + 硬件标签 | `Models/Event.swift`、`EventKitService.swift` + `AppleSyncEngine.swift` + Google/Notion sync 引擎、`TimelineView.swift`、`Core/BLE/BLEProtocol.swift` | 1d |

#### P2-1：时区变化检测
- **现状**：`LocalStorage.swift:395` 只在格式化日期时读 `TimeZone.current`，没监听系统时区变化。出差用户事件时间错位但无提示
- **决策**：监听 `NSSystemTimeZoneDidChangeNotification`，时区切换时 Toast "Time zone changed to {new}. Update your events?" + 一键调整 / 保持原样

#### P2-2：视频会议链接自动检测
- **现状**：`Event` 有 location/url 但无视频会议链接特殊识别
- **决策**：Event parsing 加正则识别 `zoom.us` / `meet.google.com` / `teams.microsoft.com` / `meet.lync.com`，标记到新字段 `Event.videoMeetingURL`；App 卡片显示 Join 按钮 deeplink；BLE `0x10` 帧只发"Video"标签节省字节

---

### P3 — 硬件联调（下次硬件 sprint）

| 项目 | 主要文件 |
|---|---|
| E-ink 字体审查 | firmware 配置、`CompanionTextService.swift` 输出 sanitize |
| BLE `0x2X full_refresh_request` 帧 + 每日首 sync 强制 | `Core/BLE/BLEProtocol.swift`、`BLESyncCoordinator.swift` |

#### P3-1：E-ink 字体审查
- **目标**：粗 sans-serif，避免细线 / Ultra Light / serif；H1/Body 字号比 ≥ 2:1；weight 700 vs 400；AA 对比度 ≥ 4.5:1
- **App 端可先做**：LLM 输出 sanitize 去 emoji / 去换行 / 限句长（已在 P0-2 字节防线部分覆盖）

#### P3-2：BLE full_refresh_request
- **目标**：协议层加 `0x2X full_refresh_request` 帧 + App 端"每天首次 sync 强制 full refresh"清残影
- **依据**：E-ink 长期使用画面"越来越脏"；partial refresh 主用 + 每 20-30 次 full refresh 是行业最佳实践

---

### Future Backlog（记住但本期不做）

- **Silent Push 服务端兜底**：APNs 证书 + Supabase Edge Function。等真出现"用户白天没开 App + 硬件晚上仍旧"反馈再做
- **CustomCompanion Kindroid 第二步 - 跨会话记忆层**：LLM 每天 summarize 关键事件存 Cascaded Memory，五层记忆架构
- **prompt 输入信息源扩展**：当前 `AIContext` 只含 tasks/events/petName/intimacyStage/recentTexts。可选扩展：HealthKit 步数/睡眠、天气、过去 7 天完成率。建议与 Kindroid 第二步同期做
- **矢量化 / 多档位 companion 形象资源**：当前 PNG 在灰阶 e-ink 低 DPI 下模糊明显，建议导出 SVG 或预渲染多档
- **Home 页 "下次 BLE sync 倒计时" 徽章**：P0-4 选择以 Settings 徽章为主而非 Home 页 BLE 倒计时；如有节流体感抱怨再加
- **What's New 启动页**：被否决（与产品哲学冲突）
- **AI 摘要风格档位**：被否决（与产品哲学冲突；CustomCompanion "说话方式"维度可吸收三档作为 preset）

---

## 验证方式

### P0 验证

**P0-1 eventLogBatch 幂等**
- 单元测试：mock 收到同 `EventLog.id` 的两条 completeTask → 第二次 skip，任务状态保持 completed
- 集成测试：App 先完成 task A → 模拟硬件回放 eventLogBatch 含 task A 的 completeTask → A 仍 completed
- 命令：`cd KirolePackage && swift test --filter "BLEEventHandlerTests"`

**P0-2 LLM 字节防线**
- 单元测试：mock LLM 返回 200 字符长句 → `enforceByteBudget(maxBytes: 120)` 后字符数 ≤ 120，且在最后一个句号截断
- 单元测试：连续 3 次超限 → fallback 触发返回 FallbackText 内容
- 命令：`cd KirolePackage && swift test --filter "CompanionTextServiceTests"`

**P0-3 BLE 分层推送**
- 模拟器测试：addTask → 立即触发 `performSync(force: true)`（spy 验证）
- 真机测试：`xcrun devicectl` 安装后加任务，BLE 抓包验证硬件即时收到 0x10
- 节流测试：BGAppRefreshTask 触发时仍按 BLESyncPolicy 节流

**P0-4 远端 sync Toast**
- UI 测试：mock Google sync 失败 → Toast 出现，Settings 徽章显示
- 集成测试：断网下点 "Sync now" → Toast + `AppState.syncErrors` 写入

### P1 验证

**P1-1 Fallback IP 切分**
- 关闭网络 → 切换 Silas pet → 触发 morningGreeting → 收到圣经意象 fallback
- Custom Companion 离线 → fallback 包含其 personaVoice 关键词

**P1-2 Custom BLE 重试**
- 模拟 BLE 断开 → push 失败入 LocalStorage 队列
- 重连事件 → 自动 flush（spy 验证 BLE write 调用）
- 硬件渲染未上线下 UI 显示明示文案

**P1-3 Roast Mode**
- 新建 CustomCompanion → 检查 `roastModeEnabled` 默认 false
- 主动开启 → 弹教育 alert

**P1-4 Kindroid 第一步**
- UI 测试：CreateCustomCompanionSheet 显示 5-8 维度 + backstory 文本框
- prompt 测试：buildSystemPrompt 包含所有用户填写的维度
- 端到端：创建一个 backstory 写"喜欢哲学但讨厌啰嗦"的 companion → 验证 LLM 输出风格符合

### P2 验证

**P2-1 时区**
- 模拟器 changeLocale → Toast 弹出
- 一键调整后事件时间正确平移

**P2-2 视频会议**
- 测试夹具：Event 含 Zoom URL → 解析后 `videoMeetingURL` 填充
- UI：事件卡片显示 Join 按钮，点击 deeplink 打开 Zoom
- BLE 抓包：0x10 帧只含 "Video" 标签

### P3 验证（硬件联调时）
- 实物对照字体可读性 + 对比度仪测量 ≥4.5:1
- 真机长期使用 30 次刷新后 full refresh 触发 + 残影清理

---

## 执行建议

**顺序**：P0 → P1 → P2 → P3。P0 内部按"基础设施成熟度"排：幂等 → 字节防线 → BLE 分层 → Toast

**风险点**
- **P1-4（Kindroid 第一步）工作量最大（2-3d）**且需 UI + prompt 双侧改动，建议放在 P1 最后做避免影响 P0/P1 早期收尾
- **P0-3（BLE 分层）依赖 `performSync(force:)` 在 BLE 未连接时的行为**，实施前先看代码确认 force=true 遇断连是入队还是丢弃

**测试要求**：每个 P0 至少一个单元测试 + 一个集成 / UI 测试。统一使用 Swift Testing（`import Testing`, `@Test`, `#expect`），不使用 XCTest

**Commit 节奏**：每个 P0/P1 项独立完成 → build → test → commit → 下一项（遵守 one-task-one-commit）

---

## 附录 A：三方交叉验证表

| 原对比点 | Kirole 仓库现状 | Inku 2026/05 现状 | 是否真差距 |
|---|---|---|---|
| 乐观更新 | App 内已乐观（`AppState+Actions.swift:168-175`） | Inku 已上 | ❌（远端 sync 是新真差距） |
| AI 摘要极简 | 部分（prompt 软约束无硬截断） | Inku 仍叙事+幽默 | ⚠️ 风格定位差异 |
| 自定义头像 | App 侧管线已通（`pushCustomAvatarFrame`） | Inku 已上 Avatar Library | ⚠️ Kindroid 路线才是差异化 |
| Roast Mode | ✅ 已实现 | Inku 是行为非模式 | ⚠️ **风险点**，默认关 + 教育 |
| 视频会议链接 | ❌ 完全未实现 | Inku 已上 | ✅ 真差距 |
| Apple Calendar | ✅ 早已接通（`EventKitService` + `AppleSyncEngine`） | Inku 已上 | ❌ 假差距 |
| 自动时区检测 | ❌ 未实现 | Inku 已上 | ✅ 真差距 |

---

## 附录 B：高置信度缺口（多 agent 撞同一处）

| 优先级 | 缺口 | 关键文件 | 撞点 agent |
|---|---|---|---|
| P0 | eventLogBatch 无幂等保护 | `BLEEventHandler.swift:261-285` | architect |
| P0 | 多类 LLM 输出无字节硬上限 | `OpenAIService.swift:336-357` | code-explorer + architect |
| P0 | 远端 sync 失败用户无感知 | `AppState+Sync.swift:113-114` | code-explorer + architect |
| P1 | Fallback 不分 IP 风格 | `FallbackText.swift` | code-explorer + architect |
| P1 | Custom Companion BLE 首推失败无重试 | `AppState+CustomCompanions.swift:142-150` | code-explorer + architect |
| P1 | Roast Mode 默认状态 + 教育文案 | `CustomCompanion.swift:12` + `OpenAIService.swift:296` | code-explorer + general-purpose |

---

## 附录 C：行业反向证据

- **Friend.com AI 项链**：嘲讽用户翻车被迫"lobotomize"角色——影响 Roast Mode 决策（默认关 + 教育）
- **Replika**：纯温暖路线被 GDPR 罚 €5M + 用户流失——证明"性格不是越无害越好"
- **Daylight DC-1**：硬件好但软件停滞 → 用户最大吐槽——支持持续迭代、What's New 价值（虽然被否决，但保留在 Future Backlog）
- **Kindroid**：47 参数 + Cascaded Memory = 深度自定义天花板——支持 CustomCompanion 走 Kindroid 路线
- **Inku Big Refresh（2025/12）**：乐观 UI + 视频会议链接 + 时区检测 + Apple Reminders + Avatar Library——证明原 7 点对比的 5 点已被 Inku 补齐
- **Tamagotchi Uni**：物理按键中心键唤醒 = 硬件优先零学习成本范例
- **Apple Watch / Pebble / Mi Band**：BLE 分层推送策略（前台即时 + 后台节流）的行业范例

---

## 附录 D：技术决策与产品哲学的连锁映射

| 决策 | 哲学投射 |
|---|---|
| eventLogBatch 幂等 | 数据正确性（基础设施） |
| LLM 字节硬截断 | 数据正确性（基础设施） |
| BLE 分层推送 | 用户主动操作的诚实反馈（基础设施） |
| 远端 sync Toast | 用户主动操作的诚实反馈（基础设施） |
| Fallback IP 切分 | IP 一致性（护城河支撑） |
| CustomCompanion 重试 | 护城河链路可靠性 |
| Kindroid 第一步 | 长期护城河 |
| 时区 / 视频会议 | 关键日历基础（用户功能） |
| Roast Mode 默认关 | 行业证据驱动的产品调整 |
| 拒绝 What's New / 风格档位 | 不为装饰投资 |
| 暂缓 Silent Push | 不为后端复杂度过高的边际收益投资 |
| 硬件离线 App 不变 | App 是 App、硬件是硬件不强行联动 |

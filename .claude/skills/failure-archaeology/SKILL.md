---
name: failure-archaeology
description: Kirole 仓库事故编年史：每次踩坑的时间线、根因、修复 commit、固化产物（543 分发事件、资产误删群、Roast Mode 误删与收敛、0x20 心跳风暴等）。用于防复发、理解现有防线为什么存在。NOT for 排查当前故障（去对应 runbook）——这是记忆库不是流程图。
---

# 失败案例考古（事故编年史）

## 适用

- 想理解某条防线/怪规则"为什么存在"
- 新事故复盘时对照历史模式
- 给新协作者（人或 agent）建立"这个仓库怎么受过伤"的直觉

## 不适用

- 正在排查现场故障 → `ble-sync-runbook` / `testflight-distribution-runbook` / `flaky-test-triage`
- 查"这个行为是否故意" → `intentional-behaviors-contract`（那是本页蒸馏出的速查表）

## 总模式：最贵的坑都是"本地信号说谎"

fastlane 的 Done ≠ 上传成功；`#if DEBUG` 缺席 ≠ TestFlight 包；grep 无引用 ≠ 资产无主；
agent 的自述 ≠ 实际 diff。本仓库所有重大防线都指向同一句话：**以外部真源（ASC API、
真机、图片本体、git diff）为准**。

## 事故 #1：TestFlight 543 —— 反馈环静默断裂 18 天（最贵）

- **时间线**：`1b8aa1c`（05-11）build 543 上线 → 持续发版，fastlane 每次 "Done" →
  外部测试者与公共链接 18 天（至 05-29）始终停在 543 → 误诊出口合规（`c82ba9e`）→
  真因 `NO_SUBMISSION`：
  分发从未提交 Beta App Review，公共链接只发最后一个 APPROVED build → `5c49e36` 根治，
  `a2a376b` 纠正误诊文档。
- **为什么最贵**：不是改坏了什么，而是**不知道自己在坑里**——18 天的迭代对外部用户为零，
  决策建立在"用户在用新版"的假象上。
- **固化产物**：Fastfile `submit_for_beta_review`（幂等）+ `status` lane（`413c928`）+
  `finish_external` lane（`cb43627`）+ 两条 memory + `testflight-distribution-runbook`。

## 事故 #2：05-07/08 身份大手术事故群

背景：产品从 Tiko/PetForm 时代切换到三 IP 体系的 48 小时里连出三起：

| 事故 | 根因 | 回滚 |
|---|---|---|
| `fd42f68` 删 5 个 tiko 资产 | "grep 无引用=占位图"的错误假设，tiko_mushroom 是客户资产 | `58fc291` |
| `90997d9` joy/silas/nova-main 被错图覆盖 | 换图时没目验图片内容 | `d6b4371` |
| `28c8753` tiko 引用全替换 + UI 改中文 | 把吉祥物体系误判为旧系统 + 违反英文 UI 规矩 | `dab7d5e` |

- **对照组**：同一时期的 streak 删除（`2d67b6e`）、evolution 删除（`6f118da`）、
  dehydration 删除是**正确**的——区别只在"谁拍的板"（PDF/客户确认 vs agent 自行假设）。
- **固化产物**：`client-asset-change-control` 全文、CLAUDE.md 资产表、memory。

## 事故 #3：Roast Mode 双重死亡（05-28）

`a959e02` 上午加 Roast Mode → code-simplifier 当"过度设计"整个删掉（连关键注释一起，
且该次运行经历过 502 中断）→ 全部还原 → 当晚 `658a2fb` 产品拍板收敛：
`CustomCompanion.roastModeEnabled` 布尔由 sensitiveBoundary 取代（**注意不是全删**——
`OnboardingProfile.customCompanionRoast:85` 与 onboarding 的 Roast Mode 开关仍在役，
别当死代码清）。同一收敛，agent 自作主张=事故、人拍板=决策。
姊妹案例：`3723af7`（04-07）"radically simplify" 砍掉人格描述，同日 `225e954` restore。
**固化产物**：`subagent-output-audit`。

## 事故 #4：0x20 心跳风暴 → 矫枉过正 → 精调（06 月底）

固件把 RequestRefresh(0x20) 当 ~2s 心跳 → App 疯狂整轮 sync → 第一刀硬抑制（`1abb44b`）
把合法刷新也压死 → 终案 60s 合并窗（`d673f80`，v2.5.14）。
**模式**：联调期修风暴类问题，第一版往往砍过头；"合并/去抖"优于"抑制"。

## 事故 #5：isTestFlight 真机不可靠（build 573）

调试开关用 `DEBUG || isTestFlight` 门控 → 真机 TestFlight 上 StoreKit 2 不写旧收据、
`appStoreReceiptURL` 文件不落地 → 门控误判 false，硬件团队拿到的包里**调试工具消失**
（keep-alive 默认值一并丢）→ `cdf1dc7` 临时放开为恒 true。
**当前状态（地雷）**：`AppBuildEnvironment.swift:36` `showsHardwareDebugTools` 恒 `true`，
**上架 App Store 前必须恢复**为 `#if DEBUG true #else isTestFlight #endif`（注释里写了改法）。

## 事故 #6：镜像解码器 desync（06-28 前后）

给 DayPack 加 DaySummary 字段时忘了同步测试层 `parseDayPack`，严格 `requireEnd()` 爆红后
补课（`fb823e1`）。**固化产物**：`ble-wire-change-control` 铁律 1 + CLAUDE.md 测试节。

## 事故 #7：非 ASCII 豆腐块（07-01）

LLM 弯引号/长破折号、用户 emoji、日历 CJK 直接上 wire → E-ink 字库缺字显豆腐块。
修法是**单点净化**：`appendString` 边界处 `StringASCIIWireSanitizer`（`c4a2b4e`），
配虚拟硬件级证明测试（`f4c45c5`、`ab6f2fa`）。**模式**：边界净化优于调用点各自处理。

## 事故 #8：静默失败家族（06-12 与 07-02 两批）

06-12 批：审计发现六条错误被吞的路径（`95e0354` 补日志）、usage state 读失败时**别用
零值覆盖**（`d8eea29`）；07-02 同族补刀：瞬态 session-restore 错误**别清 token**（`fbc2ae0`）、
outbox flush 期间入队的变更被丢（`2462a72`）、飞行中批次不落盘（`06026cf`）。
**模式**：读失败 ≠ 空数据；瞬态错误 ≠ 无效凭证；"重置成默认值"是最危险的错误处理。

## 事故 #9：毒化水位线吞掉离线补传

一条坏事件把 `lastEventLogTimestamp` 推过头，后续合法补传全被静默跳过（`7f9eb4c`）。
对硬件优先产品，补传丢失=用户操作丢失。相关测试隔离回归见 `822d086`（P0-1）。

## 事故 #10：飞书镜像漂移

`07afc24` 建"飞书友好版"协议镜像 → 漂移成误导源 → `ca09c75` 删除。
**固化产物**：单一真源 + 同步制（`docs-contract-change-control` 规则 3/4）。

## 化石层：烂尾遗迹

- `beta-release` 分支已删，但 3 个 4 个月前的 stash 还挂在它上面（`git stash list` 可见，
  tiko_avatar 时代 WIP）——可清理；
- stash@{0}（3 个月前，custom learn text WIP）——功能后来以别的形式上线，确认后可弃；
- 全仓库唯一 TODO：`LocalStorage.swift:377`（saveBehaviorSummary 0 调用者，
  behavior summary 管道休眠，`54af465` 立碑）。

## 姊妹文档

- 各 runbook / 管控文档是本页事故的"固化产物"，遇到现场问题去那边
- `intentional-behaviors-contract` — 事故与故意行为的分界清单

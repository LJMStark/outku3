---
name: intentional-behaviors-contract
description: "长得像 bug 的故意行为"清单——审计误报防御契约。看到可疑行为想修之前、写审计报告之前必查。NOT for 给新设计找借口（新决策走正常评审），也 NOT for 已知 bug 的修复流程。
---

# 故意行为契约（审计误报防御）

## 适用

- 看到一个"可疑"行为，准备当 bug 修之前
- 写/评审 audit 报告，给 finding 定级之前
- agent 提出"我发现了一个问题"时的第一道过滤

## 不适用

- 为**新**设计决策找依据 → 新决策走正常评审，本表只记录**已拍板**的历史决策
- 行为与本表描述不符 → 说明代码演化了，以最新 commit 为准，并更新本表
- 已在推迟清单里的**真 bug**（承认是问题但不修）→ 见 `subagent-output-audit` 流程 2 的推迟清单

## 速查表

| # | 行为（看起来像 bug） | 为什么是故意的 | 证据 |
|---|---|---|---|
| 1 | 硬件 SkipTask 后任务状态不变、下次还显示 | 跳过=软性"稍后再看"，不待办化、不抑制重现 | memory `project_skiptask_intentional` |
| 2 | 离线补传 replay 跳过 enterTaskIn（不启动专注） | 专注时长以 App 为准，不按硬件时间戳补算 | `guard !isReplay`，`4c20510` 文档化 |
| 3 | replay 不发通知/不回发 TaskInPage/不触发 sync | replay 只应用状态，副作用对过期事件无意义 | `b54248c`、AGENTS.md Known Inconsistencies #1 |
| 4 | App 发 Mood/PetMoodByte 但硬件不显示 | 前向兼容通道：客户保留心情模式，固件当前忽略 | v2.5.6（`3c86689`）；心情真实出口只有 PetStatus(0x01)/SmartReminder(0x13) 两字节 |
| 5 | `0x15` 出站/入站含义不同 | 字节命名空间按方向分裂，非 on-wire 冲突 | `221d44e` 专门结论 |
| 6 | 跨设备同步无并发冲突处理 | 单设备模型：换机=顺序恢复（max 合并），无多写者。"远端非单调写覆盖"类竞态**不适用本产品** | `336bb17` + AGENTS.md 红线 |
| 7 | 同步错误不弹时间线横幅 | 产品决策（2026-06）：SyncErrorBanner 已删；错误呈现=齿轮红点+Settings 行内+syncStatusCard | `5aa7d79`；别建议恢复横幅 |
| 8 | 加任务后硬件不立刻更新 | 同步节流是设计：白天 1h / 夜间 4h + 四种触发 | `ble-sync-runbook` 症状 1 |
| 9 | emoji / CJK 上 wire 被静默丢弃 | E-ink 只认 0x20–0x7E，ASCII 净化对可打印 ASCII 恒等 | `c4a2b4e`，v2.5.14 |
| 10 | Pet 页不显示 overdue 任务 | 有意排除，文档化过 | `ae05caa` |
| 11 | Pet 页下半是任务列表 UI | 客户钦定设计（Tasks Today/Upcoming/No Due Dates），不是"待办残留" | CLAUDE.md 产品身份节 |
| 12 | 硬件调试工具在所有包可见 | **临时**故意态（真机 isTestFlight 不可靠）；⚠️ 有到期日：上架前恢复门控 | `cdf1dc7`；`AppBuildEnvironment.swift:36` 注释含改法 |
| 13 | App 不发面板模式字节，固件自己判 A/B/C 态 | v2.5.15 拍板：固件本地状态机（RTC+已收数据+按键），App 只管内容与校时 | `1e5ebd6` |
| 14 | SoundService 同名音效不叠播 | 同名=先停旧再播新，语义文档化过 | `3a55de2`、`75e74aa` |
| 15 | 没有"无进化美术"的进化系统 | 硬件内置 3 个 IP 的图，App 只发信号；升档 5/15 累计天，专注每 30min +1 瓶、打断归零 | memory `project_ip_status_spec_signals`、`060e7aa`、`d3403b0` |
| 16 | AI provider 失败退 OpenRouter 兜底模型 | 已批准例外：可降级陪伴文案 + 显式配置 + 每次记日志；关键场景仍然报错不切换 | `a2e43ca`；全局规则 ai-provider-fallback |
| 17 | 结算只数**已结束**的日历事件 | 防"空任务日清晨就满分"；白天=实时进度，晚上=全量 | `699a770`、待客户确认清单附 B |
| 18 | 结算庆祝不给 launch-recovery 的会话弹 | 崩溃恢复的旧会话弹庆祝很怪 | `11599b3` |

## 使用规则

1. 报 finding 前先扫本表；命中即标注"intentional, see contract #N"并**不修**。
2. 疑似命中但细节不符 → 用 `git log -S` 找最新相关 commit，代码新于本表则代码为准。
3. 表外的可疑行为 → 正常验证流程（`subagent-output-audit` 流程 2：先验证存在，再修）。
4. 新拍板的"故意行为"（拍板人=用户/客户）→ 加进本表，带 commit 锚点。

## 姊妹文档

- `subagent-output-audit` — 推迟项清单（承认是债但不修的那批）在那边
- `failure-archaeology` — 每条故意行为背后的事故/决策故事
- `product-scope-contract` — #1/#6/#11 的产品定位依据
- `ble-sync-runbook` — #2/#3/#8/#13 的运行时细节

---
name: product-scope-contract
description: 产品红线契约：评审新功能/需求/审计建议时判断"该不该做"。含红线执法史与灰区判例。NOT for 技术实现方案评审，也不是拒绝一切新功能的挡箭牌——陪伴向增强是欢迎的。
---

# 产品范围契约（红线与判例）

## 适用

- 新功能提议、需求文档、审计建议进来时的**方向**评审
- 客户设计稿与产品定位冲突时的立场依据
- agent 提出"顺手增强一下"时的过滤器

## 不适用

- 方向已定，评审**怎么实现** → architect / 正常设计流程
- 当作拒绝一切新东西的借口——俳句、场景解锁、亲密度、屏保金句这类**陪伴向**增强
  完全符合定位，历史上都做了
- 判断单个行为是否故意 → `intentional-behaviors-contract`

## 四条红线（AGENTS.md §5 已 codify，`ecde626`）

1. **不做多入口稀释**：不做 Watch / Mac 原生端、多头像库网格、家庭共享。E-ink 是唯一日常入口。
2. **一账号 = 一活跃设备**：换机是顺序事件（max 合并恢复），不做多写者并发设计。
3. **不待办化**：不做 AI 任务拆解、详情页步骤展开、催办式提醒。task/event 只是宠物对话的
   prompt 上下文。
4. **英文 UI**：一切用户可见文案（对话/通知/横幅/按钮/E-ink）只准英文；中文只在注释和会话。

依据文件：`docs/positioning-narrative.md`（`f55f76c`，anti-todo + 可验证的不追踪信任叙事）、
`docs/Kirole显示屏页面（游戏机制2）.pdf`（客户机制真源）。

## 执法史（红线不是空话的证据）

| 判例 | 结果 |
|---|---|
| TaskDehydrationService + MicroAction（AI 任务拆解管道） | 2026-05-07 整体删除，schema 2→3 清数据 |
| Streak 连击系统（含 streakProtect 提醒、UI、Supabase 表） | `2d67b6e` 全链路删除——PDF 只有"绑定天数→prompt 风格"和"能量瓶→场景解锁"，且违反"NO penalty"原则 |
| 进化系统 | `6f118da` 删除（PDF-aligned） |
| Onboarding 里的 "AI task dehydration" 文案 | `4e0e2b8` 清洗 |
| UI 中文化 | `dab7d5e` 当天回滚，英文规矩随后 codify（`d59e414`） |
| Widget 扩展 | `62067fe` 移出 MVP（多入口方向，deferred 而非红线级禁止） |

## 灰区判例：怎么裁"待办化引力"

客户设计稿本身会带待办引力（画得像任务管理 App）。已确立的裁决模式
（见 `docs/待客户确认问题清单.md`）：

- **默认立场**：偏待办的需求先**反向提案**（例：任务中页面的"AI 任务说明"→ 折中为
  显示用户自己写的备注，而不是 AI 展开步骤）；
- **方向级分歧不自行拍板**：列大白话对比清单，客户会上定；
- **口径类小事可先实装再确认**（判例：结算计入未取消日程 → 直接实装 + 时序修正，
  仅在清单里备案）。

区分三个层级：**红线**（直接拒绝）、**方向问题**（客户拍板）、**口径细节**（实装+备案）。

## 商业化边界

计划做订阅（memory `project_kirole_subscription_planned`）：**不要**把"一次买断/永不订阅"
写进任何对外叙事或代码注释；信任叙事（不追踪/零打扰）与收费方式无关，可保留。

## 不可动的设计事实

- Pet 页布局（上宠物形象 / 下任务列表）是客户需求，照抄设计稿的产物，别"优化"；
- 三 IP 的人格规格是"客户最终版，不可漂移"（AGENTS.md §5 有逐字规格）；
- 家页伴侣槽是**单一**对话气泡（v2.5.0 收敛决策）：别提"多输出/多气泡"类增强，
  面板文本（daySummary/firstUp）一律中性、非人格。

## 姊妹文档

- `intentional-behaviors-contract` — 红线在代码层的具体表现
- `client-asset-change-control` — 客户资产=产品定位的物化，同一保护级别
- `llm-prompt-safety-contract` — 三 IP 人格在 prompt 层的落地约束
- `docs-contract-change-control` — positioning 文档的变更归属

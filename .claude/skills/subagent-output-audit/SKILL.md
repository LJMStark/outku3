---
name: subagent-output-audit
description: subagent（code-simplifier/refactor-cleaner 等）跑完后、或收到 review/audit 报告后的强制验证流程。曾有 agent 把整个功能当"过度设计"删掉。NOT for 人手写的小 diff，或用户已明确拍板的删除。
---

# Subagent 产出与审计报告验证

## 适用

- 任何 subagent（尤其 code-simplifier、refactor-cleaner 这类"帮你清理"的）执行完毕后
- 收到 LLM 生成的 review / audit / 安全报告，准备照单修复前
- agent 中途断线（502 等）后接手残局时

## 不适用

- 自己手写的小 diff → 正常 code review 流程
- 用户明确拍板过的删除 → 直接执行（但 commit message 里写明拍板来源）
- 判断"报告里说的行为是不是故意的" → 先查 `intentional-behaviors-contract`，那份是误报速查表

## 事故背景：为什么有这份文档

> code-simplifier 曾把 **Roast Mode 整个功能 + 关键注释**当"过度设计"删了（2026-05-28，
> 尤其危险的是那次 agent 还因 502 中断过——中断的 agent 报告和实际改动可能完全对不上）。
> 玩味之处：当晚产品上**真的**删了 Roast Mode（`658a2fb`，sensitiveBoundary 成为唯一开关）——
> 但那是**人拍的板**。同一个删除，agent 自作主张=事故，人拍板=决策。
>
> 同类事故：`225e954`（04-07）——"radically simplify companion prompt" 把 Role/Tone/Directives
> 人格描述简没了，当天不得不 restore。"激进简化"是 agent 的系统性倾向。

## 流程 1：subagent 跑完后

1. **别信它的自述报告**。直接 `git status` + `git diff`，审**全部**改动，不是抽查。
2. **删除类改动逐条过**：每一条删除都要能回答"为什么这不是产品功能/客户资产/故意行为"。
   拿不准的**全部还原**——恢复成本远低于事后考古（资产判定标准见 `client-asset-change-control`）。
3. **注释是资产**：机器改动会把文档注释从宿主代码上撕下来（`fd23229` 修过被常量提取
   顺手带走的 doc comment）。diff 里注释减少 = 红旗。
4. 502 / 超时中断过的 agent：假设它的自述与实际不符，从 diff 重建事实。

## 流程 2：收到 review / audit 报告后

1. **先验证再动手**：每条 finding 先 Read/grep 确认问题真实存在于当前代码。LLM 报告和
   "用户转述的事实声明"都需要验证——这是用户明确立过的规矩。
2. **对照已推迟清单**——以下均为已裁决"接受现状/故意推迟"，审计重报一律驳回，不修：
   - 2026-06 批次：A3 / B7 / B18 / secure 组 / B1 / 专注组（memory `project_core_mvp_fixes_2026-06`）
   - 2026-07 批次：云备份未接线、BLE 编排零测试、ErrorReporter public、C5 模型选择器
     （memory `project_audit_2026-07_decisions`）
   - custom-prompt 审计（build 580）：输出侧无过滤、CP-005 配额、3 个 cosmetic LOW
   - BLE 联调 572/573：H2 / H3 / H6 故意推迟
3. **对照故意行为清单**（`intentional-behaviors-contract`）：SkipTask、离线 replay 跳过、
   Mood 通道、单设备模型等是审计高频误报区。
4. 修复一律**最小改动**：改协议/上事务/造新抽象前先和用户讨论；"纯未来防御"不提前焊死。

## 流程 3：警惕"复活"类改动

stale patch / 旧上下文会把已删除的代码带回来。实例：`88d8289`（accidentally restored
AI Settings section）、`e8236a3`（accidentally re-added `#if DEBUG` guard）。
diff 里出现"新增"的代码块时，`git log -S` 查一下它是不是曾被刻意删除——
被刻意删除过的东西复活，需要拍板而不是顺手合入。

## 姊妹文档

- `intentional-behaviors-contract` — 误报速查表（本文流程 2 第 3 步的展开）
- `client-asset-change-control` — 删除类改动里资产的特殊判定
- `failure-archaeology` — Roast Mode 双重死亡、persona 简化回滚的完整记录
- `product-scope-contract` — 报告建议"增强任务功能"时的驳回依据

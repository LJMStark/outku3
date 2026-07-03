---
name: llm-prompt-safety-contract
description: LLM 管线的安全与输出契约：PromptSanitizer 注入点、输出字节预算、错误文本隔离、provider fallback 规则、custom-prompt 审计结论。碰 OpenAIService/CompanionTextService/prompt 组装前必读。NOT for 文风调优（AGENTS.md IP 规格是真源）或 OAuth/Keychain 安全。
---

# LLM Prompt 安全与输出契约

## 适用

- 改 `OpenAIService` / `CompanionTextService` / `DayPackGenerator` 的 prompt 组装
- 新增一个把用户文本送进 LLM 的路径
- 改 AI provider 配置、fallback、错误处理
- 评审涉及伴侣文本的审计报告

## 不适用

- 调三 IP 的语气/文风/字数风格 → AGENTS.md §5 "AI Companion Text System" 是逐字规格（客户最终版）
- OAuth token、Keychain、BLE HMAC → 各自的安全域，不在本页
- 判断某条 AI 行为是否故意 → `intentional-behaviors-contract`

## 输入侧：净化是结构性的，不是过滤词表

1. **所有用户可控文本**（任务标题、事件名、宠物名、learn 内容、custom persona 字段）进
   prompt 前必须过 `PromptSanitizer.sanitize(_:)`（`Core/Network/PromptSanitizer.swift`），
   当前 **8 个注入点**（AGENTS.md 计数）。新增第 9 个注入点时照此办理并更新计数。
2. 用户内容包 XML 围栏（`<user_event>…</user_event>`）且**系统提示里声明围栏语义**——
   净化+围栏+声明三件套缺一不可。
3. **custom-prompt 已审计（build 580，memory `project_custom_prompt_audit_580`）**，结论直接引用、别重审：
   - 模型套取系统提示结构：结构上不可能（结构注入已围死）；
   - **存用户原文是对的**（净化发生在使用时而非存储时）——别把"存了原文"报成漏洞;
   - 已知推迟项：输出侧无内容过滤、CP-005 配额、3 个 cosmetic LOW——**别重报**；
   - 无 key 离线走兜底文本，语义越狱在该路径测不了。

## 输出侧：预算、错误隔离、语言

1. **字节预算**：所有 LLM 伴侣输出受硬预算约束（`ea5c389` 定 120B 起，现真源为
   `DayPackTextBudget`，`BLEDataEncoder.swift:9`）。改预算走 `ble-wire-change-control` 铁律 2。
2. **错误文本永不冒充内容**：`'[Error] ...'` 这类字符串不得作为伴侣文本返回（`3c315ba`，
   连 DEBUG 包都不行——DEBUG 文案会随截图外流）；provider 错误原文不得进导出日志（`00e9a80`）。
3. **AI 输出不本地化**：伴侣对话永远英文。这就是"为什么 AI 输出从不按用户语言本地化"
   的产品原因（英文产品，见 `product-scope-contract` 红线 4）。
4. 面板文本（daySummary / firstUp）是**中性非人格**生成——宠物口吻只存在于
   `currentPetDialogue` 一句（v2.5.0 收敛）。给面板文本加人格=违反收敛决策。

## Provider 与 fallback 规则

- 主路可配 base URL + 模型（`24e37c2`，默认 OpenRouter）；失败退 OpenRouter `gpt-oss-120b`
  兜底（`a2e43ca`）。这是**已批准的例外**（可降级陪伴文案），成立条件缺一不可：
  显式配置开启、每次兜底记 `os.Logger`、兜底目标固定不漂移、仅限可降级文案。
- **取消不触发 fallback**：用户取消的请求要在 fallback 前 guard 掉（`00e9a80`），
  否则取消一次=多打一次兜底请求。
- 需要可复现/一致性/计费对账的场景：仍然报错，不切换（全局规则 ai-provider-fallback）。

## 上下文携带的约定

- custom companion 激活时（`UserProfile.customCompanionId != nil`），prompt 走
  `customCompanionPersonaPrompt`，**跳过**内置 characterPrompt；`AIContext.customCompanion`
  必须从两条入口（`CompanionTextService.generateAIText` 与
  `AppState+Companion.buildCompanionDialogueTriggerState`）都流到——历史上漏传过
  （`306b8f6` / `1c77539` 补过 DayPack 与 TaskInPage 两条线）。
- 对话缓存指纹必须含 custom id + voice 版本（`e5a29d4` 用 updatedAt 版本化、
  `7ab0e60`→`7ab9703` 用 bitPattern 处理亚秒），改人格字段时想着指纹会不会漏更新。

## 姊妹文档

- `product-scope-contract` — 三 IP 规格、单气泡收敛的产品依据
- `ble-wire-change-control` — 预算与 ASCII 净化的 wire 侧
- `intentional-behaviors-contract` — fallback 例外（#16）速查
- `subagent-output-audit` — custom-prompt 推迟项防重报

# Kirole 定位话术（内部策略参考）

> 内部策略文档，**非**逐字对外文案。提炼自 Inku 竞品分析（2026-05）。
> 所有对外文案必须英文（见 CLAUDE.md Interaction Rule 4）——下面引号里的英文行即对外文案示例。

## Hero 一句话（对外英文）

> **"Your day, with someone watching over it. No phone needed."**

把 Inku 的 "No phone needed" 与 Kirole 的宠物陪伴融合——强调「有人陪你看」，不是又一个 glanceable 工具。

## 反待办人群叙事

不是又一个催你 "just be more organized" 的日历，是一只懂你节奏、陪着你的宠物。它**陪你看一天**，不替你**管待办**。

> Inku 已经在卖 "stop fighting your brain"；Kirole 更进一步——宠物是陪伴，不是效率监工。任务/事件只是驱动宠物对话的 prompt 上下文（见 CLAUDE.md「Product Identity」）。

## vs 三方

- **vs 手机**：不响、不诱你刷。安静待着，瞄一眼就懂。
- **vs 纸质日历**：自动同步真实日历，而且宠物会说话。
- **vs 通用日历 App**：它们管待办；Kirole 陪你过日子。

## 差异化（Inku 结构上做不到的）

- 硬件点一下任务 → 宠物立刻开始陪你专注（BLE 反向触发 `0x10`）。Inku 的 Wi-Fi 显示牌做不到。
- 专注攒能量瓶子 → 解锁新场景（留存闭环）。Inku 只有 app blocker。
- 离线优先：硬件缓存操作、重连补传（`0x21`）。Inku 只有云中转。

## 信任叙事（已自查核实 2026-06-01）

核查代码库：**无任何第三方分析/追踪 SDK**（无 PostHog / Statsig / Sentry / Amplitude / Firebase）、**无 ATT / IDFA、无广告**；自定义头像照片**纯端上量化**（`AvatarImageProcessor`，从不上传）。

可诚实主张的对外英文：

> **"No cross-site tracking. Your photo never leaves your device. The hardware stays silent — no pings."**

这是相对 Inku 的道德高地（Inku 自带 PostHog / Statsig / Sentry + App Store 的 ATT 跨站追踪标签）。
> ⚠️ 维护提醒：将来若接入任何分析 SDK，必须先更新这一节，别让对外的「不追踪」承诺过期变成谎言。

## 定价 / 商业（约束）

Kirole **计划做订阅**（暂未上线）。所以**不要**用 Inku 的 "buy once / no subscription, ever" 话术（与订阅计划冲突）。信任那几句（不追踪、不打扰）与定价无关、可保留。

## 增长玩法（市场侧，不进代码）

- 把「第 4 个宠物角色 / 新解锁场景」设为预售期「社区共同解锁」stretch goal，复用现有场景解锁资产（Inku 把自定义头像设为 stretch goal，Kirole 头像已做完，真正该当目标的是新角色/场景）。

---

来源与决策依据：Inku 竞品深度对比（逐条人工裁定）。本文件只做对外叙事/定位，不触碰 task/event 数据流，不新增任何「待办增强」功能。

---
name: client-asset-change-control
description: 删除/替换/移动 图片、音频、字体等产品资产前的强制判定流程。曾因误删客户资产、IP 图错位导致多次回滚。NOT for 代码 dead path 清理（正常重构流程）或 App 图标级资产。
---

# 客户资产变更管控

## 适用

- 删除、替换、重命名 `Resources/Media.xcassets/` 下任何 imageset
- 删除音频、字体等媒体资源
- 调整 `CompanionCharacter.heroAssetName(variant:)` 的资产映射

## 不适用

- 删除无调用的 Swift 函数/类型 → 正常重构 + `subagent-output-audit` 的验证流程即可
- `Kirole/Assets.xcassets/`（App 图标、accent color）→ 风险低，常规处理
- 新增资产 → 只需遵守命名规范（见 CLAUDE.md 资产表），无需本流程

## 核心判定：grep 无引用 ≠ 可以删

这是本仓库用真事故换来的规则。**产品资产的判定标准和代码 dead path 完全不同**：

> `fd42f68`（2026-05-07，"#9 PetForm cleanup"）以"都是开发占位图"的假设删了
> `tiko_mushroom / tiko_dog / tiko_bunny / tiko_bird / tiko_dragon` 5 个 imageset。
> 实际上 **tiko_mushroom 是客户提供的产品资产**，Pet 页主图就该显示它。
> 当天 `58fc291` 用 `git checkout fd42f68^ -- ...` 紧急恢复。

删资产前必须依次回答三个问题，任何一个答不上就**停下来问用户**：

1. **来源**：这是客户提供的，还是开发期自产的占位？（客户资产往往在 `docs/UI源文件_*` / `docs/源文件`
   有对应物；`docs/*.xls` 这类客户二进制甚至不入库、只留本地+飞书，见 `30162c2`）
2. **产品文档**：`docs/Kirole显示屏页面（游戏机制2）.pdf`、UI 效果图目录里出现过它吗？
3. **确认**：用户明确说过可以删吗？"看起来没用"不算确认。

## IP 美术严格对号入座

三个 IP（joy / silas / nova）的图**绝不允许放错 imageset**。事故记录：

- `90997d9`（05-08）把 joy/silas/nova-main 覆盖成错图（蘑菇场景/无关图），`d6b4371` 从
  `63eaa05` / `5582853` 恢复；
- `5942ef9` 把本属 Silas 的阅读姿势图放进 `joy-reading`，`4ef4c1a` 移正，`00b5161` 再修一轮归属；
- 命名历史：`Nook → Joy` 在 `63eaa05`（2026-05-02）完成，**不得再引入 `nook`**。

替换任何 `joy-* / silas-* / nova-*` 图前：打开图看一眼角色特征，对照
`CompanionCharacter.heroAssetName(variant:)`（变体现状表在 CLAUDE.md），确认"这张图画的是谁"。

## Tiko ≠ 三 IP

`tiko_*` 是 App 吉祥物体系（timeline / focus / avatar / settings 多处引用），与三 IP 伴侣体系**并存**，
不是待清理的旧系统。`28c8753` 曾把全部 tiko 引用替换成 IP 图（顺手还把 UI 改成了中文），
`dab7d5e` 当天逐条 revert——revert message 里明确写了哪些保留（AppTab rawValue "Tiko"→"Kirole"）、
哪些必须还原。碰 tiko 前先读那条 revert 的 message。

## 变更清单

1. 三问判定通过（来源/产品文档/用户确认）
2. 角色对号检查（打开图目验，不靠文件名猜）
3. 若映射变化：更新 `CompanionCharacter.heroAssetName(variant:)` 与 CLAUDE.md 的变体现状表
4. 模拟器起一次，目验 Pet 页 / 时间线 / Focus / 伴侣选择页四个资产消费点 → 验收细则见 `ui-change-acceptance`
5. 单独 commit（资产 commit 不和逻辑改动混装，回滚才干净——本仓库的资产回滚全靠这点才没伤到代码）

## 姊妹文档

- `subagent-output-audit` — 自动清理类 agent 最容易犯本页错误，跑完必审
- `ui-change-acceptance` — 资产落位后的目验标准
- `failure-archaeology` — 05-07/08 资产事故群完整时间线
- `product-scope-contract` — Pet 页布局为什么不能动

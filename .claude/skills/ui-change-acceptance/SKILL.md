---
name: ui-change-acceptance
description: UI/前端改动的验收标准——什么时候才能说"改完了"。模拟器目验是硬门槛。NOT for 非 UI 逻辑（跑全量测试即可）、website/ 静态站（另一条部署链）或改动前的方向评审（product-scope-contract）。
---

# UI 改动验收标准

## 适用

- 任何 SwiftUI 视图、资产、主题、文案层面的改动，标记"完成"之前

## 不适用

- 纯逻辑/服务层改动 → 全量 `swift test` 绿即可（flaky 见 `flaky-test-triage`）
- `website/` 营销站 → 部署链见 memory `reference_kirole_website_deploy`，不走本页
- "这个 UI 该不该做" → `product-scope-contract`

## 硬门槛：模拟器目验，无一例外

**改完必须 rebuild + 起模拟器 + 亲眼看**（Development Rules #1）。没有这一步不许标完成。
XcodeBuildMCP 流程：`session_show_defaults` 确认默认 → `build_run_sim` → 截图。

## 验收清单

### 1. 文案

- [ ] 全部英文——对话、通知标题/正文、横幅、按钮、E-ink 文本。中文串曾整批混入并回滚
  （`28c8753`→`dab7d5e`），历史遗留中文是待清理债不是先例。
- [ ] 面向 E-ink 的文案满足字数纪律（多数输出 15–25 英文词，规格在 AGENTS.md）。
- [ ] 伴侣口吻只出现在对话气泡；面板/横幅文案保持中性（v2.5.0 单气泡收敛）。

### 2. 可访问性（本仓库是硬约束不是加分项）

- [ ] 每个可交互元素都有 `accessibilityLabel` **和** `accessibilityIdentifier`
  （双件套；`1da133a` 批量补过，别再欠新账）。

### 3. 环境注入

- [ ] 新的 `.sheet` / `.fullScreenCover` / `.popover` 根视图挂了 `injectAppEnvironment()`
  ——sheet 开新环境作用域，四单例**不会**自动继承，漏了就是运行时 crash/空数据。

### 4. 生命周期惯用法

- [ ] 没有 `onAppear` 里开 `Task { }`（用 `.task`）；没有 `DispatchQueue.main.asyncAfter`
  （用 `Task.sleep`）；`onChange` 用新签名。
- [ ] 视图内没有顺序化的批量存储读取（判例：`1f1511f` 从视图里移除过 37 连发的
  LocalStorage 循环——数据准备放 service/loading 层）。

### 5. 布局回归点（本仓库特有的坑位）

- [ ] 横向 `ScrollView` 页面检查 viewport 宽度锁——PetStatus / Settings / PetPage 三处
  曾集体漂移（`67cf7e1` / `fba882a` / `7ab0e60` 同日三连修）；
- [ ] 数量可变的元素不许硬编码个数：能量点曾写死 3 个（`d967f09` 改动态）、结算能量点
  上限 8 防溢出（`5e468bc`）。新的重复元素默认动态 + 上限。

### 6. 资产

- [ ] 用了新图 → 走 `client-asset-change-control`（角色对号、三问判定）；
- [ ] 消费点目验：Pet 页 / 时间线 / Focus / 伴侣选择页，哪个动了看哪个。

### 7. 主题

- [ ] 三个主题（ThemeManager）下都看过一眼，不许只验默认主题。

### 8. 测试

- [ ] 全量 `cd KirolePackage && swift test`（不是只跑相关 suite——布局/文案改动可能碰
  快照类断言，如 `HaikuSectionLayoutTests`）。

## 验收产物

commit 前的自证：模拟器截图（哪怕只给自己看）。UI commit 与资产 commit 分开
（资产回滚才不伤逻辑，见 `client-asset-change-control` 第 5 条）。

## 姊妹文档

- `client-asset-change-control` — 第 6 条的展开
- `product-scope-contract` — 改动方向的前置评审
- `flaky-test-triage` — 第 8 条跑红时
- `diagnostic-toolbox` — 模拟器/截图工具链

---
name: docs-contract-change-control
description: 修改 docs/ 下硬件契约文档（BLE通信协议规格文档.md、固件功能规格、联调指南）的流程：版本号、§ 交叉引用、飞书(lark-doc)同步、禁止镜像副本。NOT for CLAUDE.md/AGENTS.md 等 App 内部文档、positioning 产品叙事（去 product-scope-contract），或动真字节的改动（先去 ble-wire-change-control）。
---

# docs/ 硬件契约文档变更管控

## 适用

- `docs/BLE通信协议规格文档.md`（权威 wire 规格，固件团队照此施工）
- `docs/固件功能规格文档.md`、`docs/BLE初次联调指南.md`、`docs/硬件需求文档-*.md`
- 任何硬件团队会拿去当输入的文档

## 不适用

- 改动同时动了字节 → **先**走 `ble-wire-change-control`，文档更新是它的第 3 步
- CLAUDE.md / AGENTS.md / README → App 内部文档，正常改
- `docs/positioning-narrative.md` 等产品叙事 → 按普通 markdown 修改（**无需**本页的版本号/飞书流程），方向约束见 `product-scope-contract`

## 规则 1：这是施工图，不是说明文

固件团队**按字节表和 § 号施工**。历史上有两次专门的 commit 只为修交叉引用漂移
（`b06bb60` 修 stale § 指向、`8f1b293` 修 changelog 里的 stale 版本号）——说明引用网络真的在被消费。

**硬边界（客户 2026-07-23 确认）：** 如果改动不需要固件配合，BLE 字节、字段含义和固件行为均未改变，就**不得修改协议/固件文档，不得升级协议版本**。纯 App 修复只写 App 更新说明或代码提交，避免硬件团队把无需实现的内容当成新协议。

改动后自查：

1. 版本号在当前对外发布系列上递增，文档头部"状态"段落更新；
2. §1.3 修订历史表加一行，说明固件需实现、解析、适配或联调的变化；只有文字/引用纠错时，可记为文档修订，但不得把纯 App 行为写进来；
3. 全文搜索被改 § 的编号，把所有 `§x.y` 引用同步（包括固件功能规格文档里的跨文档引用）。

## 规则 2：决策写进版本历史，不另开文件

本仓库的协议决策记录（ADR）就住在协议文档的版本历史里。范例：v2.5.15 "面板态判定拍板：
**不新增 PanelMode 字节**，态 A/B/C 由固件本地状态机判定"（`1e5ebd6`）——连"为什么"
（与 Pebble Timeline / BLE CTS 同类分工一致）都写在里面。拍板类改动照此格式写，
不要新建 decision-log 文件。

## 规则 3：禁止镜像文件

`07afc24` 曾加过一份"飞书友好版"协议镜像，后来漂移成误导源，`ca09c75` 删除。
结论已固化：**协议文档单一真源在 `docs/`，飞书是同步目标不是第二份源**。
不要在根目录或任何地方新建协议文档副本；写固件对接材料前先 `ls docs/` 找现有文档做增量修改
（曾有人在根目录造重复轮子被纠正）。

## 规则 4：改完必须同步飞书

用户明确要求：改了 docs/ 协议 / 固件 / 联调文档就**主动**同步飞书，不要问 URL
（文件↔token 映射已在 memory `reference_lark_cli_feishu_doc_sync`）。要点：

- 走 `Skill(lark-doc)`，用 overwrite 模式（`docs +update` **没有 --yes flag**）；
- 同步后 fetch 回来验证内容落上了；
- CLI 的 proxy warning 会混进 stdout，解析 JSON 时用 `find('{')` 跳过前缀。

## 规则 5：客户二进制不入库

`docs/*.xls`（客户 IP 状态表等）已 gitignore（`30162c2`），保持"本地 + 飞书"双持有。
新收到的客户二进制照此办理，不要 commit 进 git。

## 变更清单

1. 版本号 + 状态段 + 修订历史表三件套
2. § 交叉引用全文同步（含固件功能规格文档的跨文档引用）
3. 若涉及字节：确认与 `BLEDataEncoder` 实现、镜像解码器一致（`ble-wire-change-control` 第 1-2 步）
4. 飞书同步 + fetch 验证
5. commit type 用 `docs(ble):` / `docs(firmware):`，message 里带版本号（沿用现有惯例）

## 姊妹文档

- `ble-wire-change-control` — 动字节时的主流程，本文档是它的第 3 步展开
- `failure-archaeology` — 镜像漂移（07afc24→ca09c75）案例
- `diagnostic-toolbox` — 联调时验证文档与固件行为一致性的工具

---
name: kirole-atlas
description: Kirole 仓库知识技能总索引/路由表。当你不确定该读哪份技能文档、或要维护这批文档时使用。NOT for 获取具体知识本体——本文只做路由，答案在目标文档里。
---

# Kirole 技能地图（Atlas）

本仓库有 15 份仓库特定技能文档（含本份），全部由 2026-07 的仓库考古产出：内容来自 commit 历史、事故记录、
memory 沉淀，**不是** CLAUDE.md / AGENTS.md 的复述。CLAUDE.md 讲"这个仓库是什么"，这批文档讲
"在这个仓库里怎么不受伤"。

## 什么时候不该用本文档

- 你已经知道要找哪个主题 → 直接打开那份，别绕路。
- 你要了解产品定位、构建命令、架构地图 → 读 `CLAUDE.md` 与 `AGENTS.md`，那是真源，本批文档不重复它们。

## 路由表：按"你正要做的事"查

| 你正要做 / 遇到的事 | 去读 | 板块 |
|---|---|---|
| 改 `encodeDayPack` / `encodeWeather` / 任何 BLE 字节 | `ble-wire-change-control` | 变更管控 |
| 删除或替换 图片 / 音频 / 字体 资产 | `client-asset-change-control` | 变更管控 |
| 改 `docs/` 下协议、固件、联调文档 | `docs-contract-change-control` | 变更管控 |
| subagent 跑完了 / 收到 review、audit 报告 | `subagent-output-audit` | 变更管控 |
| 测试忽红忽绿、只在全量跑时挂 | `flaky-test-triage` | 调试手册 |
| 硬件不显示新数据、连接/断连/补传异常 | `ble-sync-runbook` | 调试手册 |
| 测试者说"看不到新版本" | `testflight-distribution-runbook` | 调试手册 |
| 想知道这个仓库以前怎么踩坑的 | `failure-archaeology` | 失败考古 |
| 看到"像 bug"的行为，想动手修 | `intentional-behaviors-contract` | 架构契约 |
| 评审一个新功能提议 / 需求 | `product-scope-contract` | 架构契约 |
| 碰 prompt 组装、AI 输出、provider fallback | `llm-prompt-safety-contract` | 架构契约 |
| 需要工具观察现场（仿真器 / trace / ASC） | `diagnostic-toolbox` | 诊断工具 |
| UI 改完了，想标记"完成" | `ui-change-acceptance` | 验收标准 |
| 要发 TestFlight / 上架 | `release-acceptance` | 验收标准 |

## 板块间的分工原则

- **变更管控**回答"改之前要过哪些闸"；**验收标准**回答"改之后凭什么算完成"。同一件事的前闸和后闸分属两份。
- **调试手册**是按症状走的流程图；**诊断工具**是工具清单。手册引用工具，工具不含流程。
- **失败考古**是编年史（时间线 + 根因 + 固化产物），**故意行为契约**是它蒸馏出的"别修"清单。
  考古负责"为什么"，契约负责"是什么"。

## 维护规则

1. 新事故复盘 → 先记入 `failure-archaeology`（带 commit hash 与时间线），若产生"以后都要这么做"的
   规则，再升格写入对应管控/契约文档，并回链。
2. 每份文档的证据锚点是 commit hash 与 `文件:行号`。行号会漂移，hash 不会——校对时以 hash 为准。
3. 一份文档只回答一类问题。发现两份内容重叠 >30%，合并或重新划界，并更新本路由表。
4. 临时态条目（如"上架前必须恢复调试门控"）要写明**到期条件**，到期后删除条目本身。

## 姊妹文档

全部 14 份（见路由表）。本文档变更时同步检查各文档的"姊妹文档"小节是否仍然成立。

---
name: testflight-distribution-runbook
description: TestFlight 测试者拿不到新版、fastlane 上传疑似失败（ASC 上找不到 build）、build 卡审核时的排查手册（543 事件 runbook 化，核心签名 NO_SUBMISSION）。NOT for 发布前后的验收清单（去 release-acceptance）或构建/签名失败（去 swift-build-resolver）。
---

# TestFlight 分发排查手册

## 适用

- 外部测试者/公共链接说"还是旧版本"
- fastlane 显示 Done 但 ASC 上找不到 build
- build 卡在 processing / 审核状态不明

## 不适用

- 发布流程该怎么走、发完要做什么 → `release-acceptance`
- archive / 签名 / 编译失败 → swift-build-resolver agent
- App Store 正式版提审 → 流程未固化，属新领域（提醒：先恢复调试门控，见 `release-acceptance`）

## 心法：本地信号全部不可信

这份 runbook 的每一条都源于同一个教训：**fastlane 的 "Done"、本地 archive 的存在、
build 号已自增，都不是"用户能拿到"的证据**。唯一真源是 ASC API。

## 症状 1：外部测试者拿不到新版（543 事件模式）

> 时间线：`1b8aa1c`（05-11）发出 build 543 → 之后持续发版到 556+，每次 fastlane 都 "Done" →
> 外部测试者与公共链接 **18 天**（05-11→05-29）始终拿到 543 → 第一轮误诊为出口合规
> （`c82ba9e` 记录排查方向，`c2da95f` 声明 ITSAppUsesNonExemptEncryption=false）→
> 真因：分发时从未提交 Beta App Review，所有新 build 停在
> `NO_SUBMISSION`，公共链接只发最后一个 APPROVED 的 build（`5c49e36` 根治，`a2a376b` 纠正误诊文档）。

排查顺序：

1. `fastlane ios status` —— 看 `processingState` 与 external build state；
2. betaReviewState = `NO_SUBMISSION` → 就是 543 模式。跑 `fastlane ios finish_external`
   （幂等：notes upsert 和 beta-review submit 都会跳过已完成项）；
3. **别去 ASC 网页 UI 瞎猜**——用 API 查状态，这是用户立的规矩；
4. 已知非嫌疑：出口合规已永久声明（`c2da95f` `ITSAppUsesNonExemptEncryption=false`），
   别再往这个方向查。
5. 背景知识：同一版本串（如 1.0.x）已有 APPROVED build 时，后续 build 的 beta review
   是**秒批**的——所以"卡审核"几乎不可能是外部拿不到的原因，`NO_SUBMISSION` 才是。

## 症状 2：上传"成功"但 ASC 上没有

`upload_to_testflight` 可能在中途被掐死（前台跑超时、`SSL_read` EOF），结果是：
本地 build 号已自增 + archive 在磁盘上 + **ASC 上什么都没有**。

1. `fastlane ios status` 确认最新 build 号与上传时间；
2. ASC 上确实没有 → 重跑 release（SSL EOF 是瞬态，可重试）；
3. 防再发：release **必须后台/detached 跑**，别让一个前台超时掐死上传（教训已两次）；
4. build 号悬空处理：上传失败时**不要** commit 那次 bump（规矩：发布成功 + ASC 复核后才
   commit `chore(release): bump build to N`）。

## 症状 3：死在"外部分发"半路（Internal 过了、External 没走完）

SSL EOF 的另一种死法：上传+处理都成功，死在设 notes / 加外部组 / 提审这几步。
专用恢复 lane：`fastlane ios finish_external`（`cb43627` 为此而生）——
不重新 archive、不 bump，只补齐 notes + 外部组 + beta review。

## Fastfile 结构备忘（fastlane/Fastfile）

| lane | 用途 |
|---|---|
| `release` | 全流程：bump → gym → upload → notes → 外部组 + **自动提交 beta review** |
| `status` | 发布后核实（processingState / internal / external build state）|
| `finish_external` | 半路死掉后的幂等收尾 |
| `notes` | 只改 What to Test 文案 |

`distribute_to_external_groups` 里的注释就是 543 事件的尸检报告，改 Fastfile 前先读它。

## 姊妹文档

- `release-acceptance` — 正常发布的前中后验收（本页只管出事之后）
- `failure-archaeology` — 543 事件为什么是本仓库最贵的坑
- `diagnostic-toolbox` — ASC API / status lane / check_testflight_ready.sh

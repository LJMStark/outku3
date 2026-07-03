---
name: release-acceptance
description: TestFlight 发布（/release 或 fastlane）的前/中/后验收标准（全量测试绿、build 号交给 lane 自增、ASC status 复核），以及上架 App Store 前的特别闸（恢复 showsHardwareDebugTools 调试门控等）。NOT for 分发出问题后的排查（去 testflight-distribution-runbook）。本页管"凭什么算发成功"。
---

# 发布验收标准

## 适用

- 跑 `/release` 或 `fastlane ios release` 的前、中、后
- 判断"这次发布算不算成功"
- 准备第一次 App Store 正式提审时（特别闸一节）

## 不适用

- 测试者拿不到版本、上传半路死 → `testflight-distribution-runbook`（排查向）
- 发布内容本身的质量 → `ui-change-acceptance` + 全量测试

## 发布前

1. **全量测试绿**：`cd KirolePackage && swift test`（无 CI 兜底，本地就是最后一道闸）。
2. **build 号交给 lane 自增**，不手动改（`increment_build_number` 已内置；手动流程也必须
   先 increment 再 distribute——曾有不自增直接发的教训）。
3. **不要预先 commit build 号**——lane 只自增不提交，commit 属于发布成功之后（见"发布后"）。
4. Release notes 必须英文（`zh_text` 可选附加）。
5. **notes 不得出现 AI 模型/供应商名**（GPT/Claude/OpenRouter/oss/gateway…）——模型选型对外保密
   （2026-07-03 约束）；notes 从 git log 自动生成而 commit message 里有模型名，发布前人眼过一遍这条。

## 发布中

1. **后台/detached 跑**，输出重定向留档——前台跑被超时掐死会造成"本地自增了、ASC 没东西"
   的悬空态（已发生过两次）。
2. `SSL_read` EOF 是瞬态：上传阶段死 → 整体重跑；分发阶段死 → 用 `finish_external` 收尾，
   **不要**重新 archive。

## 发布后（三步缺一不可，"Done" 不算数）

1. **ASC 复核**：`fastlane ios status` —— 确认 build 号是这次的、`processingState` 正常、
   external state 不是 `NO_SUBMISSION`（beta review 已自动提交，`5c49e36` 起内置）。
2. **commit build bump**：确认落地后才提交 `chore(release): bump build to N`
   （现有惯例可考：`48d6e57` build 588、`7dd8672` build 587…）。失败的发布**不留悬空 bump**——
   此时 bump 尚未 commit，丢弃工作区里的版本号改动再重来即可。
3. **TestFlight 文档同步**：重大流程变化更新 `TESTFLIGHT_GUIDE.md` / `TESTFLIGHT_PROGRESS.md`。

## 上架 App Store 前的特别闸（一次性，但致命）

这些是联调期"临时全开"的东西，正式包**必须**关回去：

- [ ] **恢复调试门控**：`AppBuildEnvironment.swift:36` `showsHardwareDebugTools` 现在恒 `true`
  （`cdf1dc7`，build 573 起）。改回 `#if DEBUG return true #else return isTestFlight #endif`
  （改法写在同文件注释里）。不恢复=正式用户能看到硬件调试区+frame trace。
- [ ] **重新评估 keep-alive 默认值**：现默认开（`82a8d6c` 为联调设），正式包应回到省电默认。
- [ ] 出口合规**无需**再动：`ITSAppUsesNonExemptEncryption=false` 已永久声明（`c2da95f`）。
- [ ] App Store 正式提审流程本身未固化——第一次走的时候把踩的坑记回
  `failure-archaeology` 并把流程沉淀成文档。

## 其他惯例

- 公共邀请链接的语义：只发最后一个 **APPROVED** 的 build——外部感知永远滞后于内部，
  演示前先用 `status` 确认外部实际拿到的版本。
- 同版本串的后续 build beta review 秒批；**改版本号**（1.0→1.1）的第一个 build 会真人审，
  预留时间。

## 姊妹文档

- `testflight-distribution-runbook` — 本页第 1/2 步发现异常时的排查
- `failure-archaeology` — 543 事件、掐死上传的完整背景
- `diagnostic-toolbox` — status lane / 自检脚本
- `ui-change-acceptance` — 发布内容的质量前提

---
name: kirole-release
description: |
  Kirole TestFlight 发布流程（双通道）：自动生成英文说明 → 自增 build → 打包 → 上传 → 分发。
  `/release` = 内部硬件组（Kirole-Internal）；`/release external` = 外部测试组（Kirole-AppStore，与 App Store 候选同配置）。
  触发词：发布、release、ship、testflight、上传
---

# Kirole Release — TestFlight 发布

## 用法

```
/release            # 内部通道：Kirole-Internal → 只进 "Kirole Hardware Internal" 组
/release external   # 外部通道：Kirole-AppStore → 所有外部组 + Beta App Review
```

Skill 自动从 git 提交记录生成一行英文说明。参数只有 `external` 一个；不带参数即内部通道。

两条通道是**两个不同的二进制**（AGENTS.md "Release Channel Policy"）：

| 通道 | scheme / configuration | 调试工具 | 谁拿到 |
|---|---|---|---|
| internal | `Kirole-Internal` / `InternalRelease`（定义 `KIROLE_INTERNAL`） | 编译进去 | 仅内部硬件组 |
| external | `Kirole-AppStore` / `AppStoreRelease` | 编译掉 | 外部测试组；**App Store 提交直接选这个 build 号**，不再另打包 |

BLE 密钥由 `Config/Secrets.xcconfig` 的 `BLE_SECURE_CHANNEL_ENABLED` 固件就绪开关决定，与通道无关：开关为 0（固件尚未拿到密钥）时两条通道都是明文包；为 1 时 external / appstore 空密钥 fail closed。

## 执行流程

**Spawn a `claude` Agent with `model: "haiku"` to perform ALL steps below.** Pass the channel argument through verbatim.

### Haiku Agent Prompt

```
You are executing the Kirole TestFlight release workflow.
Working directory: /Users/demon/vibecoding/outku3
Channel: <"internal" unless the user passed "external">

STEP 1 — Generate English release notes (ONE line, max 80 chars):
Run: git log --oneline -20
Look at the commit messages since the last version bump (commits after the most recent "chore: bump" or build-number change).
Summarize the user-facing changes into ONE concise English sentence.
Rules:
- Start with a capital letter, no period at end
- Focus on what changed for the user (bug fixes, UI changes, new features)
- If only internal/infra changes, write: "Performance improvements and bug fixes"
- NEVER mention AI model, provider, or vendor names (GPT/Claude/OpenRouter/oss/gateway/...) even
  if commit messages do — model choices are confidential (2026-07-03 约束). Describe the effect
  instead, e.g. "Improved companion dialogue reliability"
- Examples: "Bug fixes and UI improvements"
           "Fixed pet reading pose and improved timeline display"
           "New companion character artwork and stability improvements"

STEP 2 — Run the fastlane lane for the channel:
Execute via Bash (timeout 600000ms, run_in_background: true so a foreground timeout cannot kill the upload):
  internal: fastlane ios internal text:"<generated notes from Step 1>"
  external: fastlane ios external text:"<generated notes from Step 1>"
The external lane first runs scripts/verify-release-boundary.sh (two simulator builds, several minutes) — this is expected, do not abort.

STEP 3 — Report result:
- SUCCESS (output contains "Done — internal build" / "Done — external build"): Report "Build NNN 已发布 ✓（<channel>）说明：<notes>"
- FAILURE: Report the error lines (lines starting with [!] or "error:")
- Then run `fastlane ios status` and report the per-channel processingState / externalBuildState — a "Done" line alone is not proof the build landed.
```

## 流水线内部步骤（fastlane 自动完成）

1. （external 专有）`require_ble_secret_if_secure_channel_enabled` + `scripts/verify-release-boundary.sh`
2. `increment_build_number` — build number 自动 +1
3. `gym` — Xcode 打包，约 3 分钟
4. `upload_to_testflight` — 上传 + 等待 Apple 处理，约 5 分钟
5. 写入 en-US 说明（`zh_text:` 可选）
6. internal：加入 "Kirole Hardware Internal"（手动分配组）；external：加入所有外部组 + 提交 Beta App Review

## 注意事项

- 需要 Mac 本地环境 + Xcode + 签名证书
- `fastlane/.env` 必须存在（含 ASC 密钥）
- 外部测试组首次需通过 Apple beta review（通常数小时）；同一版本串已过审的后续 build 秒批
- 发布成功 + `status` 复核后才提交 `chore(release): bump build to N`；失败别留悬空 bump

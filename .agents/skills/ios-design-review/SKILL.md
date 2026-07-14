---
name: ios-design-review
version: standalone-1.0.0
description: Real-device iOS visual design audit using Apple HIG and the standalone DebugBridge.
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - AskUserQuestion
---

## 项目内运行路径

本 Skill 复用项目内的 `ios-qa` 实体目录：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
IOS_QA_SKILL_ROOT="$PROJECT_ROOT/.agents/skills/ios-qa"
STANDALONE_SKILL_STATE="${STANDALONE_SKILL_STATE:-$PROJECT_ROOT/.agents/skill-state}"
export STANDALONE_SKILL_STATE
```

# iOS Design Review

使用 `$IOS_QA_SKILL_ROOT/bin/standalone-ios-qa-daemon` 连接设备，只执行观察请求。

对每个主要页面获取截图和元素树，并按 0–10 评分：字体层级、间距节奏、颜色层级、触控尺寸、加载/空/错误状态、无障碍、动效、iOS 习惯、信息密度和 AI 套模板痕迹。每项都写出“做到 10 分还需要什么”。

报告写到 `$STANDALONE_SKILL_STATE/projects/<slug>/ios-design-review-<date>.md`，包含截图、逐屏评分、最大收益改动和未验证页面。

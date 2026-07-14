---
name: ios-sync
version: standalone-1.0.0
description: Regenerate the standalone iOS DebugBridge templates and typed accessors.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
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

# Resync the iOS DebugBridge

1. 读取应用 `DebugBridgeGenerated/.standalone-version`；缺失时按未知旧版本处理。
2. 使用 `$IOS_QA_SKILL_ROOT/scripts/gen-accessors-tool` 重新生成访问器。
3. 从 `$IOS_QA_SKILL_ROOT/templates` 更新 Swift 模板；遇到用户标记的编辑先展示差异再覆盖。
4. 运行 `swift build`、应用构建和状态 schema 检查。

这是本地模板同步，不执行网络更新、不读取遥测、不调用核心包路径。

---
name: ios-clean
version: standalone-1.0.0
description: Remove the standalone iOS DebugBridge and verify a clean Release build.
allowed-tools:
  - Bash
  - Read
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

# Strip the DebugBridge from an iOS app

先列出将要删除的依赖、`#if DEBUG` wiring、生成的访问器和临时 token，等待用户确认。

批准后：

1. 移除 DebugBridge SPM 依赖及 target 引用。
2. 移除 Debug 配置下的启动 wiring 和生成的 `StateAccessor.swift`。
3. 删除应用临时目录中的 `standalone-ios-qa.token`（设备在线时尽力执行）。
4. 运行 Release 构建，确认没有 DebugBridge 符号。

不改动业务逻辑、ViewModel、普通测试或其他 QA 设施。

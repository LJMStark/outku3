---
name: ios-fix
version: standalone-1.0.0
description: Autonomous iOS bug fixer that reproduces, patches, rebuilds, and verifies on device.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
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

# Autonomous iOS Bug Fixer

依赖 `ios-qa` 的发现，但不依赖任何已删除的 Skill。

1. 读取发现，恢复设备状态，保存修复前快照和截图。
2. 按根因调查流程追踪 Swift 数据流，未确认根因前不改代码。
3. 最小化修改，重新构建、安装并通过 `$IOS_QA_SKILL_ROOT/bin/standalone-ios-qa-daemon` 连接设备。
4. 恢复修复前状态重新验证；最多尝试三轮，仍失败就停止并报告。
5. 保存修复后截图，并在 `test/fixtures/ios-fix` 增加回归测试。

设备断开、构建失败或状态 schema 不匹配时，保留现场并说明下一步。

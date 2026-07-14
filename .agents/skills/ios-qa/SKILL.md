---
name: ios-qa
version: standalone-1.0.0
description: Live-device iOS QA using the standalone DebugBridge and CoreDevice tunnel.
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

本 Skill 不依赖全局框架或用户目录中的共享运行时。使用项目内唯一实体目录：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
IOS_QA_SKILL_ROOT="$PROJECT_ROOT/.agents/skills/ios-qa"
STANDALONE_SKILL_STATE="${STANDALONE_SKILL_STATE:-$PROJECT_ROOT/.agents/skill-state}"
export STANDALONE_SKILL_STATE
```

# Live-device iOS QA

通过独立运行时的 DebugBridge、StateServer 和 CoreDevice IPv6 tunnel 连接真实 iPhone。

## 流程

1. 读取应用 Swift 源码，识别 `@Observable` 和 `@Snapshotable` 字段。
2. 使用 `$IOS_QA_SKILL_ROOT/scripts/gen-accessors-tool` 生成访问器。
3. 仅在 Debug 配置安装 DebugBridge，接入 StateServer、截图、元素树和状态快照。
4. 构建、安装并启动应用，运行 `$IOS_QA_SKILL_ROOT/bin/standalone-ios-qa-daemon`。
5. 通过截图、元素树和状态快照执行“观察→操作→验证”循环；每次写操作都先获取 session 锁。
6. 记录复现步骤、截图、状态和风险；完成后释放锁。

状态、审计和临时文件写入 `$STANDALONE_SKILL_STATE`，不写入全局状态目录。没有真机时执行静态检查和代码生成测试，并报告真机测试未执行。

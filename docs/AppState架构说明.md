# AppState 架构说明

更新日期：2026-05-08

## 现状概览

AppState 是 Kirole App 的全局状态中心，跨 8 个扩展文件，约 2100 行。  
它不是"上帝类"——它是有意识的 Facade，把多个子系统的读写入口统一暴露给 SwiftUI 视图树。

### 文件结构

| 文件 | 职责 |
|---|---|
| `AppState.swift` | 属性定义、服务引用、持久化助手 |
| `AppState+Actions.swift` | 任务/事件的增删改、同步触发 |
| `AppState+Companion.swift` | 宠物对话、Haiku、共享对话缓存刷新 |
| `AppState+CustomCompanions.swift` | 自定义伴侣的创建/选择/删除、头像像素帧（0x15）BLE 推送 + 失败重发退避 |
| `AppState+HardwareDisplay.swift` | BLE/硬件同步触发（sendFocusStatus、sendScreensaverConfig 等） |
| `AppState+Integrations.swift` | Google/Apple/Notion/Taskade 集成状态判断 |
| `AppState+Loading.swift` | 本地数据加载、统计刷新、天气更新 |
| `AppState+Profile.swift` | 用户 Profile、Onboarding 完成标记 |
| `AppState+Sync.swift` | 外部数据源同步（Google/Apple/Notion/Taskade）、BLE 防抖请求 |

---

## 服务归属（2026-05-08 现状）

以下子系统已从 AppState 独立出去，有专属 @Observable 单例：

| 能力 | 归属 |
|---|---|
| 专注会话 + 能量瓶子 + `focusEnforcementMode` | `FocusSessionService.shared` |
| BLE 连接/发包/协议 | `BLEService.shared` + `BLESyncCoordinator.shared` |
| 宠物状态计算 | `PetManager`（被 AppState 持有）|
| 任务列表操作 | `TaskManager`（被 AppState 持有）|
| 场景解锁 | `SceneUnlockService.shared` |
| 屏保配置 | `ScreensaverService.shared` |

### focusEnforcementMode 迁移说明

原来在 `AppState.focusEnforcementMode`（存储属性），现在已移到 `FocusSessionService.focusEnforcementMode`。

AppState 保留同名**计算属性**转发，保持所有视图代码不变：
```swift
// AppState.swift（只读转发，不存储）
public var focusEnforcementMode: FocusEnforcementMode {
    FocusSessionService.shared.focusEnforcementMode
}
```

`BLEEventHandler` 直接读 `FocusSessionService.shared.focusEnforcementMode`，不再依赖 AppState。

---

## SwiftUI 环境注入体系

### 注入点

**ContentView（根）**：同时注入 Observable-style 和 Key-style：
```swift
// Observable-style（支持 @Environment(AppState.self) 读法）
.environment(appState)
.environment(themeManager)
.environment(authManager)
.environment(FocusSessionService.shared)

// Key-style（支持 @Environment(\.appState) 读法 + 测试注入覆盖）
.environment(\.appState, appState)
.environment(\.themeManager, themeManager)
.environment(\.authManager, authManager)
.environment(\.focusService, FocusSessionService.shared)
```

**Sheet/Cover/Popover 根 View**：必须调用 `.injectAppEnvironment()`，否则 AppState 等对象在新 environment scope 里不可见。

### 读法

```swift
// 现有视图（Observable-style，绝大多数视图用这种）
@Environment(AppState.self) private var appState
@Environment(ThemeManager.self) private var theme

// 新代码（Key-style，可在测试中覆盖）
@Environment(\.focusService) private var focusService
@Environment(\.appState) private var appState
```

### 测试注入覆盖

```swift
// 测试里覆盖 AppState（不影响其他 view）
MyView()
    .environment(\.appState, mockAppState)
    .environment(\.focusService, mockFocusService)
```

---

## 目标架构（待实施，非当前状态）

用户在 2026-05-08 选择了「全部拆开成多个小管家」，以下是目标方向，供未来实施参考。

### 计划拆出的子状态

| 子状态 | 属性迁移目标 | 优先级 |
|---|---|---|
| `PetState` | `pet`, `petManager` | 中 |
| `TaskState` | `tasks`, `events`, `statistics`, `taskManager` | 高（跨引用多，需仔细） |
| `SyncState` | `weather`, `sunTimes`, `integrations`, `lastError`, `activeSyncs` | 低 |
| `UIState` | `selectedTab`, `selectedDate`, `isLoading`, `hasCompletedInitialHomeLoad` | 低 |
| `FocusSessionService`（已有） | `focusEnforcementMode`（已迁） | ✅ 已完成 |

### 关键风险（拆前必读）

1. **toggleTaskCompletion 跨 4 个子状态**：同时写 tasks、pet、statistics、currentHaiku。  
   拆分后需要 AppState Facade 协调，不能让子状态直接互相引用。  
   注：2026-06 起带 `source: TaskToggleSource` 参数——`.hardwareReplay`（BLE 离线事件回放）只应用状态变更，跳过声音/震动与 currentHaiku 生成；拆分时两条路径都要保留。

2. **FocusSessionService 调用 AppState.syncFocusHardwareDisplay**（第 92、96 行）：  
   拆分后如果 AppState 消失，此处要改为直接调 BLEService/SimulatorBridge。

3. **Sheet 注入**：全局 grep `injectAppEnvironment` 查所有注入点，拆分后需同步更新。

4. **BLEEventHandler 仍依赖 `AppState.shared`**（handleSingleEvent、persistEventLogs 等）：  
   这些调用短期内保留 AppState.shared 是可以的，长期目标是全部改为调专属服务。

---

## 关键约束（来自 CLAUDE.md）

- NO ViewModels
- `@MainActor` 用于 UI 状态
- `actor` 用于共享可变状态（LocalStorage 是 actor）
- Sheet/Cover 根 View 必须 `.injectAppEnvironment()`
- 用户输入文本进 prompt 前必须过 `PromptSanitizer.sanitize(_:)`

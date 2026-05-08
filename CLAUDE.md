# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The authoritative rules, architecture notes, and command reference live in `./AGENTS.md`.
Read it before any non-trivial change. `.cursor/rules/*.mdc` contains additional
Swift/SwiftUI/Testing/Concurrency guidance that applies here too.

## Interaction Rules
1. Every response must begin with **B哥**.
2. Respond in **Simplified Chinese**. For non-technical questions, keep language plain and explain jargon inline.
3. Treat `/Users/demon/vibecoding/outku3` as the strict workspace boundary. Unqualified requests ("build", "commit", "run tests") always refer to this repo.

## Product Identity (READ FIRST)
Kirole 是 **硬件优先的宠物陪伴产品**：硬件 E-ink 设备是用户主要的日常交互入口，App 是给硬件配置数据的工具。任务和日历事件主要作为 **prompt 上下文** 驱动宠物对话，**不是给用户管理待办用的**。任何把 task/event 当"待办"来增强（AI 任务拆解、详情页步骤展开、待办清单视图、催促式提醒等）的提议都偏离产品定位，应直接拒绝或反向清理。

**硬件优先意味着**：硬件离线时用户操作不能丢——硬件本地缓存事件，BLE 重连后通过 `0x21 eventLogBatch` 帧批量回推给 App，App 必须把每条事件应用到 AppState（任务完成状态、专注会话等）。"补传"是核心功能而非可选项。

三条核心数据流（基于代码事实，2026-05-07 用户与多 agent 调研共同验证）：

1. **任务/事件 → Prompt → 宠物对话**
   `appState.tasks/events` → `DayPackGenerator` → `CompanionTextService` → `OpenAIService.buildCompanionUserPrompt`（8 个 `PromptSanitizer` 注入点之一是 `taskTitle` / `topTaskTitles` / `nextAgendaItem`）→ 输出 `morningGreeting` / `dailySummary` / `companionPhrase` → 显示在 `HaikuSectionView` / `TimelineView`，并通过 BLE 推送给硬件。

2. **App → 硬件同步有节流，不立刻 push**
   `BLESyncCoordinator.performSync()` + `BLESyncPolicy` 节流：白天 08-23 每 1 小时一次；夜间 23-08 每 4 小时一次。触发时机：(a) iOS `BGAppRefreshTask` 后台唤醒；(b) 硬件主动发 `0x20 requestRefresh` / `0x30 deviceWake`；(c) DayPack 内容指纹（`stableFingerprint()`）变化或 `force: true`。**用户加一个任务后，硬件不会立刻显示**，要等下一个 sync 时机。

3. **硬件 → App 反向触发专注模式**
   硬件 E-ink 屏点击进入某任务 → 发 `0x10 enterTaskIn` → `BLEEventHandler.handleSingleEvent` → `handleFocusSessionEvent` → `FocusSessionService.startSession(taskId:, taskTitle:, mode:, startTime:)` → App 自动进入专注模式（30 分钟阈值 / 屏幕解锁监测 / 能量瓶子发放 / 场景解锁庆祝 整套链路自动启动）。同时 `handleEnterTaskIn` 回推 `TaskInPage` 数据让硬件展示任务详情+鼓励语。

## Development Rules
1. After any frontend / UI change, rebuild and launch the simulator to visually verify. Do not mark UI work complete without this check.
2. The project is in rapid iteration: `LocalStorage`, `UserDefaults`, on-device JSON, and BLE payload shapes are disposable. Prefer resetting local data over writing migration shims until hardware/TestFlight consumers exist (see AGENTS.md §2 "Current Phase Policy").

## Architecture at a Glance
- Workspace + SPM: `Kirole.xcworkspace` opens everything; app shell lives in `Kirole/`, all feature code in `KirolePackage/Sources/KiroleFeature/`. New code almost always belongs in the package.
- UI stack: SwiftUI with **Model-View only** — no ViewModels. State flows through four `@Observable` singletons injected at `ContentView`: `AppState`, `ThemeManager`, `AuthManager`, `FocusSessionService`. Any view that might read them needs all four in its environment. See "Environment Values Keys" in AGENTS.md §3 for typed `EnvironmentKey` access patterns (Wave 3, 2026-05-08).
- Key subsystems (detail in AGENTS.md §3): Timeline (`TimelineDataSource` + `HomeView`), 14-screen onboarding (`OnboardingState`), Pet/Companion IP system (3 IP characters Joy/Silas/Nova × 5 stages × 5 moods × 4 Pet scenes), Companion text pipeline (`DayPackGenerator` → `CompanionTextService` → `OpenAIService`), BLE sync (`BLEPacketizer`/`BLESyncCoordinator`), Focus mode (`FocusSessionService` + `DisplayScene`), Supabase persistence.
- Views exposed from `KirolePackage` to the app shell must be `public`.

## Hard Constraints (do not violate)
- NO ViewModels, NO XCTest (use Swift Testing: `import Testing`, `@Test`, `#expect`), NO CoreData/CloudKit, NO Combine unless strictly required.
- **NO `Task { }` inside `onAppear`** — use `.task` modifier (auto-cancels with view lifecycle). Replace `DispatchQueue.main.asyncAfter` with `Task { try? await Task.sleep(for: ...) }` inside `.task`.
- NO secrets in `Info.plist`. Secrets come from `Config/Secrets.xcconfig` (git-ignored) via `AppSecrets.configure(...)`.
- NO manual file adding to Xcode targets — `KirolePackage` uses buildable folders.
- Concurrency: `@MainActor` for UI, `actor` for shared state, avoid `@unchecked Sendable`.
- Accessibility: every interactive element needs `accessibilityLabel` and `accessibilityIdentifier` (add `accessibilityHint` when the action is non-obvious).
  - **A11y Coverage**: 25 core view files (Home, Timeline, Pet, Settings, Onboarding) updated with 118 accessibility annotations (2026-05-08). Other view files pending in subsequent iterations.

## Sheet / FullScreenCover Environment Injection
`.sheet`, `.fullScreenCover`, and `.popover` create a new SwiftUI environment scope — the four singletons are **not inherited automatically**. Every sheet/cover root view must chain:

```swift
.environment(AppState.shared)
.environment(ThemeManager.shared)
.environment(AuthManager.shared)
.environment(FocusSessionService.shared)
```

The `injectAppEnvironment()` modifier in `Views/Modifiers/InjectAppEnvironment.swift` wraps all four (both Observable-style and Key-style variants).

**For testing**, you can inject mocks via typed environment keys:
```swift
.environment(\.appState, mockAppState)
.environment(\.themeManager, mockThemeManager)
.environment(\.authManager, mockAuthManager)
.environment(\.focusService, mockFocusService)
```

## LLM Prompt Safety
All user-controlled text (task titles, event names, pet names, learn content) **must pass through `PromptSanitizer.sanitize(_:)` before interpolation into any LLM prompt**. Wrap user content in XML delimiters (`<user_event>…</user_event>`) and declare the fence in the system prompt. `PromptSanitizer` lives in `Core/Network/PromptSanitizer.swift`.

## Supabase (Self-Hosted on Zeabur)
The project uses a **self-hosted Supabase** instance, not Supabase Cloud.
- **API gateway (Kong 2.8.1)**: `https://outku3.zeabur.app`
- **Auth (GoTrue v2.180.0)**: `/auth/v1`
- **REST (PostgREST)**: `/rest/v1` — tables: `pets`, `sync_state`
- **Schema source of truth**: `Config/supabase-schema.sql` — apply manually to Zeabur PostgreSQL when schema changes.
- **OAuth proxy**: Notion and Taskade token exchange goes through Supabase Edge Functions (`supabase/functions/notion-oauth/` and `supabase/functions/taskade-oauth/`). `client_secret` is server-side only — never in the binary.

## Common Commands
Prefer XcodeBuildMCP tools when available; otherwise use the CLI fallback.

Build & run (simulator):
```bash
# Fast package-only compile
cd KirolePackage && swift build

# Full app build on simulator
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Tests:
```bash
# Full package test suite (Swift Testing)
cd KirolePackage && swift test

# Single test
cd KirolePackage && swift test --filter "MyTestSuite/testMethod"

# Simulator test run (only-testing filter)
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:KiroleFeatureTests/MyTestSuite/testMethod
```

Real device install (after simulator verification):
```bash
xcrun devicectl device install app --device <DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphoneos/Kirole.app
```

## Where to Look Next
- `AGENTS.md` — full rules, BLE protocol, Joy/Silas/Nova companion IP paradigm, onboarding detail.
- `.cursor/rules/*.mdc` — Swift / SwiftUI / Testing / Concurrency / XcodeBuildMCP guidance.
- `TESTFLIGHT_GUIDE.md`, `TESTFLIGHT_PROGRESS.md` — release workflow state.

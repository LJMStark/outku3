# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The authoritative rules, BLE protocol, and full subsystem detail live in `./AGENTS.md`.
Read it before any non-trivial change. `.cursor/rules/*.mdc` adds Swift/SwiftUI/Testing/Concurrency guidance.

## Interaction Rules
1. Every response must begin with **B哥**.
2. Respond in **Simplified Chinese**. For non-technical questions, keep language plain and explain jargon inline.
3. Treat `/Users/demon/vibecoding/outku3` as the strict workspace boundary. Unqualified requests ("build", "commit", "run tests") always refer to this repo.

## Product Identity (READ FIRST)
Kirole 是 **硬件优先的宠物陪伴产品**：硬件 E-ink 设备是用户主要的日常交互入口，App 是给硬件配置数据的工具。任务和日历事件主要作为 **prompt 上下文** 驱动宠物对话，**不是给用户管理待办用的**。任何把 task/event 当"待办"来增强（AI 任务拆解、详情页步骤展开、催促式提醒等）的提议都偏离产品定位，应直接拒绝或反向清理。

**Pet 页面布局是设计内容（客户需求，勿动）**：上半部分显示宠物形象，下半部分是任务列表 UI（Tasks Today / Upcoming / No Due Dates，含 checkbox / Edit / Delete）。这是刻意的产品设计，不是"待办增强"。

**硬件优先意味着**：硬件离线时用户操作不能丢——硬件本地缓存事件，BLE 重连后通过 `0x21 eventLogBatch` 帧批量回推给 App，App 必须把每条事件应用到 AppState（任务完成状态、专注会话等）。"补传"是核心功能而非可选项。

三条核心数据流：

1. **任务/事件 → Prompt → 宠物对话**
   `appState.tasks/events` → `DayPackGenerator` → `CompanionTextService` → `OpenAIService.buildCompanionUserPrompt` → 输出 `morningGreeting` / `dailySummary` / `companionPhrase` → 显示在 `HaikuSectionView` / `TimelineView`，并通过 BLE 推送给硬件。

2. **App → 硬件同步有节流，不立刻 push**
   `BLESyncCoordinator.performSync()` + `BLESyncPolicy`：白天 08-23 每 1 小时；夜间 23-08 每 4 小时。触发时机：iOS `BGAppRefreshTask`、硬件主动发 `0x20`/`0x30`、DayPack 指纹变化或 `force: true`。**用户加任务后硬件不会立刻显示**，要等下一个 sync。

3. **硬件 → App 反向触发专注模式**
   硬件点击任务 → `0x10 enterTaskIn` → `BLEEventHandler` → `FocusSessionService.startSession(...)` → 整套专注链路自动启动。

## Development Rules
1. After any frontend / UI change, rebuild and launch the simulator to visually verify. Do not mark UI work complete without this check.
2. The project is in rapid iteration: `LocalStorage`, `UserDefaults`, on-device JSON, and BLE payload shapes are disposable. Prefer resetting local data over writing migration shims until hardware/TestFlight consumers exist (see AGENTS.md §2 "Current Phase Policy").

## Architecture at a Glance

### Package Structure
- **Workspace**: Open `Kirole.xcworkspace`. App shell in `Kirole/`; all feature code in `KirolePackage/Sources/KiroleFeature/`.
- New code almost always belongs in the package. No manual file adding to Xcode targets — `KirolePackage` uses buildable folders.
- Views exposed from `KirolePackage` to the app shell must be `public`.

```
KiroleFeature/
├── Core/
│   ├── AppEnvironmentValues.swift   # EnvironmentKey definitions for all 4 singletons
│   ├── Auth/                        # Google/Apple sign-in
│   ├── BLE/                         # BLEProtocol.swift ONLY — App→Device/Device→App byte definitions (source of truth)
│   ├── Network/                     # OpenAIService, PromptSanitizer, SupabaseService
│   ├── Services/                    # BLE runtime lives here (BLEService, BLESyncCoordinator, BLEEventHandler, BLEPacketizer, BLEConnectionPolicy, BLESecurityManager…) + FocusSessionService, CompanionTextService, DayPackGenerator…
│   └── Storage/                     # LocalStorage, AppSecrets
├── Models/                          # AppState+*.swift extensions, CompanionCharacter, Pet, Task…
├── State/                           # TimelineDataSource, OnboardingState
├── Views/                           # Home/, Pet/, Settings/, Onboarding/, Modifiers/
└── Resources/                       # Media.xcassets (image assets)
```

> **BLE byte namespaces are direction-split.** `Core/BLE/BLEProtocol.swift` (`BLEDataType`) defines App→Device bytes; Device→App bytes live in `Models/EventLog.swift` (`EventLogType.rawByte`). The **same byte value can mean different things by direction** — e.g. `0x15` is CustomAvatarFrame (outbound) vs ViewEventDetail (inbound). This is intentional and not an on-wire conflict; don't flag it as one.

### State Management
Four `@Observable` singletons injected at `ContentView` via `.environment()`:

| Singleton | Purpose |
|-----------|---------|
| `AppState` | Tasks, events, pet, navigation — split across `AppState+Actions/Sync/Loading/HardwareDisplay/Profile/Companion.swift` |
| `ThemeManager` | 3 themes |
| `AuthManager` | Apple / Google Sign In |
| `FocusSessionService` | Focus session state, enforcement mode, energy bottles |

**AppState extension map** — where to put code:
- User-triggered mutations → `AppState+Actions.swift`
- Remote sync (Google/Apple/Notion/Taskade) → `AppState+Sync.swift`
- Initial data loading → `AppState+Loading.swift`
- BLE / DisplayScene / hardware push → `AppState+HardwareDisplay.swift`
- Profile and companion text → `AppState+Profile.swift` / `AppState+Companion.swift`
- Custom companion avatar BLE push → `AppState+CustomCompanions.swift`
- Persistence helpers (`persistTasks`, `persistPet`) → `AppState.swift` main file

### UI Stack
SwiftUI with **Model-View only** — no ViewModels. Tab-based nav via `AppState.selectedTab`. Custom `AppHeaderView` fixed at top (outside `ScrollView`); no native `TabView`.

### CompanionCharacter Image Asset Naming
Assets live in `Resources/Media.xcassets/<name>.imageset/`. Naming convention: `<rawValue>-<variant>` where `rawValue` is `joy` / `silas` / `nova`.

Variants: `main`, `head`, `reading`, `profile`, `sunrise`, `sunset`, `scene`.

**Always assign art to the correct character's imageset. Never place Silas art in `joy-*` or vice versa — this has caused multiple rollback commits.**

Current per-variant state (source of truth: `CompanionCharacter.heroAssetName(variant:)`):

| Variant | Joy | Silas | Nova |
|---------|-----|-------|------|
| `.reading` | `joy-reading-2.png` (575KB) — timeline & focus pose | `silas-reading.png` (754KB) | `nova-reading.png` |
| `.profile` | falls back to `joy-main` (no dedicated art yet) | `silas-profile.png` (46KB) | falls back to `nova-main` |
| `.main` | `joy-main.png` — standing pose; **not** used on the home timeline | `silas-main.png` | `nova-main.png` |
| `.sunrise`/`.sunset` | `joy-sunrise/sunset.png` | `silas-sunrise/sunset.png` | `nova-sunrise/sunset.png` |

The home timeline pet embed and Focus mode both use `.reading`. PetStatusView uses `.profile`.

## Hard Constraints (do not violate)
- NO ViewModels, NO XCTest (use Swift Testing: `import Testing`, `@Test`, `#expect`), NO CoreData/CloudKit, NO Combine unless strictly required.
- **NO `Task { }` inside `onAppear`** — use `.task` modifier. Replace `DispatchQueue.main.asyncAfter` with `Task { try? await Task.sleep(for: ...) }` inside `.task`.
- **NO deprecated `.onChange(of:perform:)`** — use `.onChange(of:) { oldValue, newValue in ... }`.
- NO secrets in `Info.plist`. Secrets come from `Config/Secrets.xcconfig` (git-ignored) via `AppSecrets.configure(...)`.
- Concurrency: `@MainActor` for UI, `actor` for shared state, avoid `@unchecked Sendable`.
- Accessibility: every interactive element needs `accessibilityLabel` and `accessibilityIdentifier`.

## Sheet / FullScreenCover Environment Injection
`.sheet`, `.fullScreenCover`, `.popover` create a new SwiftUI environment scope — singletons are **not inherited automatically**. Use the `injectAppEnvironment()` modifier (`Views/Modifiers/InjectAppEnvironment.swift`) on every sheet/cover root view. For testing, inject mocks via typed keys:

```swift
.environment(\.appState, mockAppState)
.environment(\.themeManager, mockThemeManager)
.environment(\.authManager, mockAuthManager)
.environment(\.focusService, mockFocusService)
```

## LLM Prompt Safety
All user-controlled text (task titles, event names, pet names, learn content) **must pass through `PromptSanitizer.sanitize(_:)` before interpolation into any LLM prompt**. Wrap user content in XML delimiters (`<user_event>…</user_event>`) and declare the fence in the system prompt. `PromptSanitizer` lives in `Core/Network/PromptSanitizer.swift`.

## Supabase (Self-Hosted on Zeabur)
- **API gateway (Kong)**: `https://outku3.zeabur.app`
- **REST**: `/rest/v1` — tables: `pets`, `sync_state`
- **Schema source of truth**: `Config/supabase-schema.sql` — apply manually to Zeabur PostgreSQL when schema changes.
- **OAuth proxy**: Notion / Taskade token exchange via Supabase Edge Functions (`supabase/functions/`). `client_secret` is server-side only.

## Common Commands

Prefer XcodeBuildMCP tools when available. Before the first build in a session, always call `session_show_defaults` to confirm project/scheme/simulator are set.

### Build & Run (simulator)
```bash
# Fast package-only compile
cd KirolePackage && swift build

# Full app build
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Tests
```bash
# Full package test suite (Swift Testing)
cd KirolePackage && swift test

# Single test
cd KirolePackage && swift test --filter "MyTestSuite/testMethod"

# Simulator run (with filter)
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:KiroleFeatureTests/MyTestSuite/testMethod
```

### TestFlight Release (Full Pipeline)
```bash
# Full release: auto-increment build → archive → upload → set notes → distribute external group
# /release slash command (auto-generates English notes from git log, uses Haiku model)
/release

# Or via fastlane directly (English notes required; zh_text optional)
fastlane ios release text:"Bug fixes and UI improvements"
fastlane ios release text:"English notes" zh_text:"中文说明"

# Notes-only update (no build, no distribution)
fastlane ios notes text:"说明内容"
```

Pipeline steps (automated): `increment_build_number` → `gym` (archive ~3 min) → `upload_to_testflight` (processing ~5 min) → set en-US + zh-Hans notes → distribute to external group **kirole**.

Credentials: `fastlane/.env` (git-ignored) — copy from `fastlane/.env.template` and fill `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.

**Verify the build actually landed.** `upload_to_testflight` can be killed mid-upload (process timeout / transient `SSL_read` EOF), leaving the build number bumped locally + an archive on disk but **nothing on App Store Connect** — a "Done" line or local archive is not proof. Confirm via the ASC API (latest build number + `processing_state` + beta-review state). Run the release detached/in background so one timeout can't kill the upload; transient SSL errors are retryable.

### Real Device Install
```bash
xcrun devicectl device install app --device <DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphoneos/Kirole.app
```

## Config / Secrets Setup
Create `Config/Secrets.xcconfig` (git-ignored) with:
```
DEVELOPMENT_TEAM = 93SL23NPNG
GOOGLE_CLIENT_ID = ...
GOOGLE_REVERSED_CLIENT_ID = ...
SUPABASE_URL = ...
SUPABASE_ANON_KEY = ...
BLE_SHARED_SECRET =         # leave empty for dev (unsigned frames)
OPENAI_API_KEY = ...        # OpenRouter key used by OpenAIService
```

For TestFlight automation, copy `fastlane/.env.template` → `fastlane/.env` and fill in `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.

## Where to Look Next
- `AGENTS.md` — full rules, BLE protocol spec, companion IP prompt architecture, onboarding detail, Focus Mode state machine, Event→Output dispatch map.
- `.cursor/rules/*.mdc` — Swift / SwiftUI / Testing / Concurrency / XcodeBuildMCP guidance.
- `TESTFLIGHT_GUIDE.md`, `TESTFLIGHT_PROGRESS.md` — release workflow state.

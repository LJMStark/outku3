# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
For agent workflow and interaction rules, see `AGENTS.md`.

## Interaction Rules

1. **称呼**：所有回复必须以 "B哥" 开头。
2. **语言**：所有回复必须使用中文（简体）。

## Forbidden Patterns

- **NO ViewModels**: Use `@Observable` models directly in Views
- **NO `Task { }` in `onAppear`**: Use `.task` modifier
- **NO deprecated `.onChange(of:perform:)`**: Use `.onChange(of:) { oldValue, newValue in ... }` or `.onChange(of:) { ... }`
- **NO CoreData**: Use SwiftData or raw persistence
- **NO XCTest**: Use Swift Testing (`import Testing`)
- **NO Combine**: Unless strictly necessary
- **NO secrets in `Info.plist`**: Never place `OPENROUTER_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BLE_SHARED_SECRET` in app plist

## Project Overview

**Kirole** is an iOS companion app for an E-ink hardware device. It helps remote workers build habits through AI-powered pixel pet companionship and gamified task management.

- **Platform**: iOS 17.0+ (iPhone only)
- **Language**: Swift 6.1+ with strict concurrency
- **UI Framework**: SwiftUI with Model-View (MV) pattern - no ViewModels
- **Testing**: Swift Testing framework (`@Test`, `#expect`, `#require`)

## Build & Test Commands

When XcodeBuildMCP tools are available, prefer them over raw xcodebuild:

```javascript
// Build and run on simulator (preferred)
build_run_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kirole.xcworkspace",
    scheme: "Kirole",
    simulatorName: "iPhone 17 Pro"
})

// Run tests on simulator
test_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kirole.xcworkspace",
    scheme: "Kirole",
    simulatorName: "iPhone 17 Pro"
})
```

Fallback to raw commands when XcodeBuildMCP is unavailable:

```bash
# Swift Package only (fast iteration)
cd KirolePackage && swift build
cd KirolePackage && swift test

# Full app build - Simulator
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Full app test
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run single test (package - fast)
cd KirolePackage && swift test --filter "AppStateTests/testToggleTaskCompletion"

# Run single test (simulator - thorough)
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:KiroleFeatureTests/AppStateTests/testToggleTaskCompletion

# Real device build & deploy
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS,id=<DEVICE_ID>' -allowProvisioningUpdates build

xcrun devicectl device install app --device <DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphoneos/Kirole.app

# List available devices
xcrun xctrace list devices
```

## Architecture

### Workspace + SPM Package Structure

```
outku3/
├── Kirole.xcworkspace/          # Open this in Xcode
├── Kirole/                      # App shell (minimal - just entry point)
│   └── KiroleApp.swift
├── KirolePackage/               # ALL development happens here
│   ├── Package.swift
│   └── Sources/KiroleFeature/
│       ├── ContentView.swift   # Root view with environment injection
│       ├── State/AppState.swift
│       ├── Models/             # Pet, Task, Event, DayPack, EventLog, FocusSession, AIMemory, UserProfile, MicroAction, OnboardingProfile
│       ├── Design/Theme.swift
│       ├── Core/               # Services (Auth, API, Storage, BLE)
│       └── Views/
│           ├── Home/, Pet/, Settings/, Components/
│           └── Onboarding/
│               ├── OnboardingContainerView.swift  # Page router (15 screens)
│               ├── Logic/OnboardingState.swift     # @Observable navigation + profile state
│               ├── Data/OnboardingQuestions.swift   # 8 questionnaire definitions
│               ├── Components/                     # 11 shared components
│               └── Pages/                          # 8 page views (Screen 0-14)
├── Config/
│   ├── Shared.xcconfig         # Bundle ID, version, deployment target
│   ├── Secrets.xcconfig        # API keys (git-ignored)
│   └── Kirole.entitlements      # App capabilities
└── docs/                       # Hardware specs, BLE protocol
```

### State Management

Three singletons injected via `.environment()` from ContentView:

| Singleton | Purpose |
|-----------|---------|
| `AppState` | Pet, tasks, events, navigation, integrations |
| `ThemeManager` | Current theme colors (3 themes) |
| `AuthManager` | Authentication state (Apple/Google Sign In) |

Views access via `@Environment(AppState.self)`, `@Environment(ThemeManager.self)`, `@Environment(AuthManager.self)`.

**Important**: All three must be injected for any view that might need them. Missing environment injection causes runtime crashes.

### Navigation & Layout

- Tab-based navigation via `AppState.selectedTab` (`.home`, `.pet`, `.settings`)
- Custom header (`AppHeaderView`) with tab buttons - no TabView
- **Header is fixed at top** - placed outside ScrollView in each main page

### Home Timeline Architecture

Home page is an infinite-scroll multi-day timeline managed by `TimelineDataSource`:

- `HomeView` → `LazyVStack` with today (offset 0) followed by `ForEach(offset 1+)`
- `DaySectionView(date:, showPet:)` → `DateDividerView` + `DayTimelineView`
- `DayTimelineView(date:, events:, showPet:)` → sunrise/events/sunset, with `HaikuSectionView` (haiku text + tiko pet image) embedded after the 2nd event card when `showPet: true`
- Today always has `showPet: true`; subsequent days show pet every 3 days via `TimelineDataSource.shouldShowPetMarker(at:)`
- All timeline components (`DayTimelineView`, `HaikuSectionView`, `TimelineEventRow`, etc.) live in `Views/Home/TimelineView.swift`

### Key Services

| Service | Purpose |
|---------|---------|
| `AuthManager` | Apple Sign In + Google Sign In |
| `EventKitService` | Apple Calendar & Reminders |
| `GoogleCalendarAPI` | Google Calendar sync |
| `GoogleTasksAPI` | Google Tasks sync |
| `OpenAIService` | Haiku + AI companion text generation (GPT-4o-mini) |
| `CompanionTextService` | Personalized text with OpenAI fallback to local templates |
| `BehaviorAnalyzer` | User behavior summary from task/focus data |
| `SupabaseService` | Cloud data persistence |
| `CloudKitService` | iCloud sync (lazy-loaded) |
| `BLEService` | E-ink device communication |
| `BLEDataEncoder` | Data encoding (Pet, Task, DayPack) |
| `BLEEventHandler` | Event parsing, Focus Session events |
| `BLESyncCoordinator` | Scheduled BLE sync flow with retry |
| `BLESyncPolicy` | Time-window sync scheduling logic |
| `BLEBackgroundSyncScheduler` | BGTask scheduling for BLE sync |
| `BLEPacketizer` | BLE payload chunking + CRC header |
| `BLEPacketAssembler` | Reassemble incoming chunks into payloads |
| `BLESecurityManager` | BLE v2 handshake + secure envelope (HMAC + nonce) |
| `BLEDeviceIdentityStore` | Trusted/blocklist device identity storage |
| `BLERateLimiter` | BLE write/request rate limiting |
| `DayPackGenerator` | Generate daily data for E-ink device |
| `FocusSessionService` | Track task focus time with screen activity |
| `TaskDehydrationService` | AI task decomposition into What/When/Why micro-actions |
| `SmartReminderService` | Context-aware reminders (deadline/streak/idle/nudge) |

## Supabase Rules

- iOS 客户端运行时配置由 App 壳层调用 `AppSecrets.configure(...)` 注入（来自构建期常量）。
- 严禁在 `Info.plist`、`Bundle.infoDictionary`、日志或任何前端可见配置中放置 `OPENROUTER_API_KEY`、`SUPABASE_URL`、`SUPABASE_ANON_KEY`、`BLE_SHARED_SECRET`。
- 构建期密钥来源（环境变量 / `Config/Secrets.xcconfig` / `Kirole/BuildSecrets.generated.swift`）不得提交真实值。
- 严禁在客户端、仓库、日志、`Info.plist` 或任何前端可见配置中使用/暴露 `service_role` 高权限密钥。
- 所有业务表必须启用 RLS，并按 `auth.uid()` 进行数据隔离。
- 任何 `SupabaseClient` 数据模型字段变更（新增/重命名/删除）必须在同一个提交中同步更新 `Config/supabase-schema.sql`。
- 对已存在数据库必须提供向后兼容迁移语句（例如 `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`），避免线上/新环境 schema 漂移导致运行时失败。
- 发版前先执行 schema/migration，再发布客户端，避免出现 “代码写入新字段但数据库无该列” 的同步故障。

## Code Patterns

### SwiftUI State (MV Pattern)

```swift
struct MyView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Text(appState.pet.name)
            .foregroundStyle(theme.colors.primaryText)
    }
}

// For bindings to @Observable
@Bindable var appState = appState
Toggle(isOn: $appState.someProperty)
```

### Async Operations

Always use `.task` modifier, never `Task { }` in `onAppear`:

```swift
.task {
    do {
        try await loadData()
    } catch {
        // Handle error
    }
}
```

### Public API

Types exposed to app target need `public` access:

```swift
public struct NewView: View {
    public init() {}
    public var body: some View { ... }
}
```

### Fixed Header Layout

Main pages must keep header outside ScrollView:

```swift
var body: some View {
    VStack(spacing: 0) {
        AppHeaderView()  // Fixed at top

        ScrollView {
            // Scrollable content
        }
    }
    .background(theme.colors.background)
    .ignoresSafeArea(edges: .top)
}
```

## Swift 6 Concurrency

- Use `@MainActor` for all UI-related code
- Use `actor` for shared mutable state (e.g., `LocalStorage`)
- Use `.task` modifier in views (auto-cancels on disappear)
- Never use `Task {}` in `onAppear`
- Ensure `Sendable` conformance for types crossing concurrency boundaries
- Avoid `@unchecked Sendable` unless there is no practical alternative; if used, document why the type is truly thread-safe

## BLE Protocol & Sync (Hardware Requirements)

- Packet header (9 bytes, big-endian): `type (UInt8)`, `messageId (UInt16)`, `seq (UInt8)`, `total (UInt8)`, `payloadLen (UInt16)`, `crc16 (UInt16)`
- CRC16-CCITT-FALSE (poly `0x1021`, init `0xFFFF`, xorout `0x0000`, refin/refout `false`)
- Always send via `BLEPacketizer` and assemble via `BLEPacketAssembler` before parsing payloads.
- BLE security mode is dual-track:
  - **Compatibility Mode (MVP default)**: no `BLE_SHARED_SECRET` configured, allows legacy plaintext protocol for firmware integration.
  - **Secure Mode**: `BLE_SHARED_SECRET` configured, requires BLE v2 handshake and signed secure envelopes.
- Event Log record format: `eventType (UInt8)`, `timestamp (UInt32, epoch seconds)`, `value (Int16, big-endian)`
- BLE data types include `eventLogRequest` and `eventLogBatch` for incremental log sync.
- Sync policy: 08:00–23:00 hourly; 23:00–08:00 every 4 hours; 30s connection window.
  - Computed by `BLESyncPolicy`, executed by `BLESyncCoordinator`.
- DayPack refresh must be gated by `DayPack.stableFingerprint()` and `LocalStorage.lastDayPackHash`.
- BGTask identifier: `com.kirole.app.ble.sync` (requires `bluetooth-central` background mode).
- Spectra 6 pixel encoding: 4bpp (2 pixels per byte), color index: Black=0x0, White=0x1, Yellow=0x2, Red=0x3, Blue=0x5, Green=0x6
- Frame buffer size: width * height / 2 bytes (4寸: 120,000 bytes, 7.3寸: 192,000 bytes)

## Onboarding Flow (15 Screens)

15-screen onboarding ported from React + Framer Motion (`temp/app/`), fully native SwiftUI.

| Screen | View | Description |
|--------|------|-------------|
| 0 | `WelcomePage` | Teal bg, FloatingIconRing, CharacterView + dialog, CTA "I'm Ready!" |
| 1 | `FeatureCalendarPage` | 3 staggered DialogBubbles, bouncing arrows |
| 2 | `FeatureFocusPage` | BeforeAfterCard (tap-to-flip), blue-monster |
| 3 | `PersonalizationPage` | Theme picker (ThemePreviewCard) + Avatar selector |
| 4 | `KickstarterPage` | Kickstarter stats card + funded badge |
| 5 | `TextAnimationPage` | Dark bg, 7-line sequential text animation, tap to continue |
| 6-13 | `QuestionnairePage(questionIndex:)` | Data-driven from OnboardingQuestions (8 questions) |
| 14 | `SignUpPage` | Google Sign In + Apple/Email placeholders |

Key types:
- `OnboardingState` (`@Observable @MainActor`): manages `currentPage` (0-14), `direction`, `profile`, `soundEnabled`
- `OnboardingProfile`: 9 enums + all questionnaire fields, persisted via `LocalStorage`
- `OnboardingContainerView`: routes pages via `switch`, transitions with `.id()` + `.transition(.asymmetric)` + `.animation(.spring)`
- `OnboardingQuestions.allQuestions`: 8 questions with categories (Profile / Habits & Goals / Personalization)

Image assets in `Resources/Media.xcassets/`: inku-main, inku-head, blue-monster, avatar-boy/dog/girl/robot/toaster, kickstarter-card. Access via `Image("name", bundle: .module)`.

## Theme System

3 themes: Classic Warm (default), Elegant Purple, Modern Teal.

Access colors via `theme.colors.propertyName`:
- `background`, `cardBackground`, `primaryText`, `secondaryText`
- `accent`, `timeline`, `sunrise`, `sunset`
- `taskComplete`, `streakActive`

## Pet System

- 5 forms: Cat, Dog, Bunny, Bird, Dragon
- 5 stages: Baby → Child → Teen → Adult → Elder
- 5 moods: Happy, Excited, Focused, Sleepy, Missing You
- 4 scenes: Indoor, Outdoor, Night, Work

## AI Companion Text System

`CompanionTextService` generates personalized text (greetings, summaries, encouragement, etc.) using a two-tier approach:

1. **OpenAI path** (when API key configured): Builds `AIContext` from `UserProfile` (companionStyle, workType, goals) + app state, calls `OpenAIService.generateCompanionText()` with style-aware prompts (4 personalities: encouraging/strict/playful/calm), saves `AIInteraction` to `LocalStorage` for memory
2. **Local fallback** (no key or API failure): Returns from hardcoded template arrays (original behavior)

Key flow: `DayPackGenerator` -> `CompanionTextService` -> `OpenAIService` (optional) -> `LocalStorage` (AI interactions)

- `TaskDehydrationService` decomposes tasks into `MicroAction` (What/When/Why) via `OpenAIService.dehydrateTask()`, with 24h cache in `LocalStorage` and fallback to task title
- `SmartReminderService` evaluates 4 trigger conditions in priority order: deadline → streakProtect → idle → gentleNudge, rate-limited to 30min intervals, sends via `BLEDataEncoder.encodeSmartReminder()` (0x13 command)
- `FocusSessionService.statistics` provides expanded metrics: `averageSessionMinutes`, `longestSessionMinutes`, `interruptionCount`, `peakFocusHour`, `focusTrendDirection` (compared to yesterday via date-keyed session storage)

- `BehaviorAnalyzer` is a pure `struct` that computes `UserBehaviorSummary` from tasks/streak data for prompt injection
- `TimeOfDay.current(at:)` is the shared time-of-day utility (defined on the `TimeOfDay` enum in `DayPackGenerator.swift`) - use this instead of manual hour switches
- `LocalStorage` uses generic `save<T>`/`load<T>` helpers for all JSON persistence - follow this pattern for new data types
- All `CompanionTextService` methods accept `userProfile: UserProfile = .default` to maintain backward compatibility

## E-ink Hardware Integration

### Hardware Specs
- **Product form**: 4寸 / 7.3寸 two sizes
- **4寸 screen**: 400 x 600 pixels, E Ink Spectra 6, 4bpp full color (6 colors: Black, White, Yellow, Red, Blue, Green)
- **7.3寸 screen**: 800 x 480 pixels, E Ink Spectra 6, 4bpp full color (6 colors)
- **SoC**: ESP32-S3, Flash >= 16MB, PSRAM >= 2MB
- **RTC**: Built-in RTC for timekeeping when BLE disconnected
- **Interaction**: Power button + Encoder knob (rotary + press) + BLE to iOS App

### Hardware Docs
- `docs/硬件需求文档-Hardware-Requirements-Document.md` (v0.3): 硬件电气需求（SoC、显示、电源、电池）
- `docs/固件功能规格文档.md` (v1.3.0): 固件功能规格（页面设计、交互流程、宠物系统）
- `docs/BLE通信协议规格文档.md` (v1.3.1): BLE 通信协议（命令格式、数据结构、事件定义）

### BLE Protocol
- Service UUID: `0000FFE0-0000-1000-8000-00805F9B34FB`
- See `docs/BLE通信协议规格文档.md` for full protocol

### Key Models
- `DayPack`: Daily data package sent to device (includes micro-action and focus metrics in fingerprint)
- `MicroAction`: AI-decomposed task step with What (40 chars), When, Why (60 chars), estimatedMinutes
- `EventLog`: Events received from device (task completion, etc.)
- `DeviceMode`: Interactive vs Focus mode
- `FocusSession`: Track focus time per task (30-min threshold for phone inactivity)

## Testing

```swift
import Testing

@Test func petEvolvesOnTaskCompletion() async throws {
    let state = AppState.shared
    let initialProgress = state.pet.progress
    state.toggleTaskCompletion(state.tasks[0])
    #expect(state.pet.progress > initialProgress)
}
```

## Configuration

### Secrets Configuration

Create `Config/Secrets.xcconfig` (git-ignored) with:
```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
GOOGLE_CLIENT_ID = xxx.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.xxx
SUPABASE_URL = https://xxx.supabase.co
SUPABASE_ANON_KEY = eyJxxx
```

### Backend Services Status

| Service | Status | Config Location |
|---------|--------|-----------------|
| Google Sign In | Configured | `Config/Secrets.xcconfig` |
| Supabase | Configured | `Config/Secrets.xcconfig` |
| OpenAI | Optional | User enters in Settings |
| Sign in with Apple | Pending | Requires paid Apple Developer ($99/yr) |

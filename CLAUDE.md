# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
For agent workflow and interaction rules, see `AGENTS.md`.

## Interaction Rules

1. **称呼**：所有回复必须以 "佛山王力宏" 开头。
2. **语言**：所有回复必须使用中文（简体）。

## Forbidden Patterns

- **NO ViewModels**: Use `@Observable` models directly in Views
- **NO `Task { }` in `onAppear`**: Use `.task` modifier
- **NO CoreData**: Use SwiftData or raw persistence
- **NO XCTest**: Use Swift Testing (`import Testing`)
- **NO Combine**: Unless strictly necessary

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
│       ├── Models/             # Pet, Task, Event, DayPack, EventLog, FocusSession, AIMemory, UserProfile
│       ├── Design/Theme.swift
│       ├── Core/               # Services (Auth, API, Storage, BLE)
│       └── Views/              # Home, Pet, Settings, Onboarding, Components
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
| `ThemeManager` | Current theme colors (5 themes) |
| `AuthManager` | Authentication state (Apple/Google Sign In) |

Views access via `@Environment(AppState.self)`, `@Environment(ThemeManager.self)`, `@Environment(AuthManager.self)`.

**Important**: All three must be injected for any view that might need them. Missing environment injection causes runtime crashes.

### Navigation & Layout

- Tab-based navigation via `AppState.selectedTab` (`.home`, `.pet`, `.settings`)
- Custom header (`AppHeaderView`) with tab buttons - no TabView
- **Header is fixed at top** - placed outside ScrollView in each main page

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
| `DayPackGenerator` | Generate daily data for E-ink device |
| `FocusSessionService` | Track task focus time with screen activity |

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
- Use `@unchecked Sendable` for thread-safe types that can't prove it to compiler

## BLE Protocol & Sync (Hardware Requirements)

- Packet header (9 bytes, big-endian): `type (UInt8)`, `messageId (UInt16)`, `seq (UInt8)`, `total (UInt8)`, `payloadLen (UInt16)`, `crc16 (UInt16)`
- CRC16-CCITT-FALSE (poly `0x1021`, init `0xFFFF`, xorout `0x0000`, refin/refout `false`)
- Always send via `BLEPacketizer` and assemble via `BLEPacketAssembler` before parsing payloads.
- Event Log record format: `eventType (UInt8)`, `timestamp (UInt32, epoch seconds)`, `value (Int16, big-endian)`
- BLE data types include `eventLogRequest` and `eventLogBatch` for incremental log sync.
- Sync policy: 08:00–23:00 hourly; 23:00–08:00 every 4 hours; 30s connection window.
  - Computed by `BLESyncPolicy`, executed by `BLESyncCoordinator`.
- DayPack refresh must be gated by `DayPack.stableFingerprint()` and `LocalStorage.lastDayPackHash`.
- BGTask identifier: `com.kirole.app.ble.sync` (requires `bluetooth-central` background mode).
- Spectra 6 pixel encoding: 4bpp (2 pixels per byte), color index: Black=0x0, White=0x1, Yellow=0x2, Red=0x3, Blue=0x5, Green=0x6
- Frame buffer size: width * height / 2 bytes (4寸: 120,000 bytes, 7.3寸: 192,000 bytes)

## Theme System

5 themes: Cream (default), Sage, Lavender, Peach, Sky.

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

### BLE Protocol
- Service UUID: `0000FFE0-0000-1000-8000-00805F9B34FB`
- See `docs/BLE-Protocol-Spec.md` for full protocol

### Key Models
- `DayPack`: Daily data package sent to device
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

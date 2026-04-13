# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The core project rules, architecture, development commands, and best practices are defined in `./AGENTS.md`. Always read it first and follow it strictly for consistency across tools.

## Interaction Rules

1. All responses must begin with **B哥**.
2. All responses must be in **Chinese** (Simplified).
3. When the user sounds non-technical or asks for a simple explanation, prefer plain Chinese, explain jargon immediately, and avoid dense technical terms unless they are necessary.

## Forbidden Patterns

- **NO ViewModels**: Use `@Observable` models directly in Views
- **NO `Task { }` in `onAppear`**: Use `.task` modifier
- **NO deprecated `.onChange(of:perform:)`**: Use `.onChange(of:) { oldValue, newValue in ... }` or `.onChange(of:) { ... }`
- **NO CoreData**: Use SwiftData or raw persistence
- **NO XCTest**: Use Swift Testing (`import Testing`)
- **NO Combine**: Unless strictly necessary
- **NO CloudKit/iCloud**: Removed for MVP; use Supabase for cloud persistence
- **NO secrets in `Info.plist`**: Never place `OPENROUTER_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BLE_SHARED_SECRET` in app plist

## Project Overview

**Kirole** is an iOS companion app for an E-ink hardware device. It helps remote workers build habits through AI-powered pixel pet companionship and gamified task management.

- **Platform**: iOS 17.0+ (iPhone only)
- **Language**: Swift 6.1+ with strict concurrency
- **UI Framework**: SwiftUI with Model-View (MV) pattern - no ViewModels
- **AI Backend**: OpenRouter (`openai/gpt-4o-mini`) via `OpenAIService`
- **Testing**: Swift Testing framework (`@Test`, `#expect`, `#require`)

## Current Phase Policy

- The project is in a rapid development phase. Prefer clean iteration over preserving local caches, local JSON files, or provisional interfaces.
- `LocalStorage`, `UserDefaults`, and on-device JSON are disposable development state. When their schema changes, reset them instead of adding migration code.
- BLE payloads, event formats, and firmware-facing interfaces are not frozen until real hardware integration starts. Do not preserve historical firmware compatibility before that point.
- Remove stale compatibility shims, migration comments, and migration tests when replacing local models or payloads.
- Only start preserving formats once hardware integration, shared staging data, TestFlight, or external users depend on them.

## Apple Developer Account

- **Account Type**: Paid Apple Developer Program ($99/year)
- **Email**: xiaoyouzi2010@gmail.com
- **Team ID**: 93SL23NPNG
- **Team Name**: Jiaming Liang
- **Status**: Active
- **Capabilities**: Can publish to TestFlight and App Store
- **Family Controls**: Distribution version application submitted
  - Application submitted: 2026-02-26
  - Approval status: Pending review (1-2 weeks)
  - Progress tracking: See TESTFLIGHT_PROGRESS.md

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
│       ├── State/              # AppState (split into extensions), ThemeManager, etc.
│       ├── Models/             # Pet, Task, Event, DayPack, EventLog, FocusSession, AIMemory, UserProfile, MicroAction, OnboardingProfile
│       ├── Design/Theme.swift
│       ├── Core/
│       │   ├── Auth/           # AuthManager
│       │   ├── Config/         # AppSecrets
│       │   ├── Network/        # OpenAIService, CompanionTextService, Google APIs, Notion/Taskade
│       │   ├── Services/       # BLE*, FocusSession, DayPack, SmartReminder, EventKit, etc.
│       │   └── Storage/        # LocalStorage
│       └── Views/
│           ├── Auth/           # Sign-in flows
│           ├── Home/           # HomeView, TimelineView (HaikuSectionView), PromptDebuggerView
│           ├── Pet/            # Pet status and interaction
│           ├── Settings/       # App settings
│           ├── Components/     # Shared UI components
│           └── Onboarding/     # 14-screen onboarding flow
├── Config/
│   ├── Shared.xcconfig         # Bundle ID, version, deployment target
│   ├── Secrets.xcconfig        # API keys (git-ignored)
│   └── Kirole.entitlements     # App capabilities
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

- `HomeView` -> `LazyVStack` with today (offset 0) followed by `ForEach(offset 1+)`
- `DaySectionView(date:, showPet:)` -> `DateDividerView` + `DayTimelineView`
- `DayTimelineView(date:, events:, showPet:)` -> sunrise/events/sunset, with `HaikuSectionView` (renders either the daily haiku or shared pet dialogue above the tiko pet image) embedded after the 2nd event card when `showPet: true`
- Today always has `showPet: true`; subsequent days show pet every 3 days via `TimelineDataSource.shouldShowPetMarker(at:)`
- All timeline components (`DayTimelineView`, `HaikuSectionView`, `TimelineEventRow`, etc.) live in `Views/Home/TimelineView.swift`

### Key Services

| Service | Purpose |
|---------|---------|
| `AuthManager` | Apple Sign In + Google Sign In |
| `EventKitService` | Apple Calendar & Reminders |
| `GoogleCalendarAPI` | Google Calendar sync |
| `GoogleTasksAPI` | Google Tasks sync |
| `OpenAIService` | Haiku + AI companion text generation (OpenRouter `openai/gpt-4o-mini`) |
| `CompanionTextService` | Personalized text with OpenAI fallback to local templates |
| `BehaviorAnalyzer` | User behavior summary from task/focus data |
| `SupabaseService` | Cloud data persistence |
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

- Client runtime config injected via `AppSecrets.configure(...)` from App shell (build-time constants).
- Never place `OPENROUTER_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BLE_SHARED_SECRET` in `Info.plist`, logs, or any frontend-visible config.
- Build-time secret sources (`Config/Secrets.xcconfig`, env vars, `Kirole/BuildSecrets.generated.swift`) must never commit real values.
- Never use or expose `service_role` keys in iOS code, app bundles, repo files, or logs.
- Keep RLS enabled on all business tables and scope policies to `auth.uid()`.
- Any Supabase model field change must update `Config/supabase-schema.sql` in the same patch.
- During rapid development, prefer a clean latest schema over backward-compatible migration shims.
- Before shared staging data, external testers, or production data exist, breaking schema changes are acceptable if code and `Config/supabase-schema.sql` stay aligned.
- Once external environments depend on the schema, switch to explicit migrations and preserve existing data intentionally.

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
  - **Development Mode (current default)**: no `BLE_SHARED_SECRET` configured, allows unsigned transport for local development. This does not imply support for historical firmware variants.
  - **Secure Mode**: `BLE_SHARED_SECRET` configured, requires BLE v2 handshake and signed secure envelopes.
- Event Log record format: `eventType (UInt8)`, `timestamp (UInt32, epoch seconds)`, `value (Int16, big-endian)`
- BLE data types include `eventLogRequest` and `eventLogBatch` for incremental log sync.
- Sync policy: 08:00-23:00 hourly; 23:00-08:00 every 4 hours; 30s connection window.
  - Computed by `BLESyncPolicy`, executed by `BLESyncCoordinator`.
- DayPack refresh must be gated by `DayPack.stableFingerprint()` and `LocalStorage.lastDayPackHash`.
- BGTask identifier: `com.kirole.app.ble.sync` (requires `bluetooth-central` background mode).
- Spectra 6 pixel encoding: 4bpp (2 pixels per byte), color index: Black=0x0, White=0x1, Yellow=0x2, Red=0x3, Blue=0x5, Green=0x6
- Frame buffer size: width * height / 2 bytes (4-inch: 120,000 bytes, 7.3-inch: 192,000 bytes)

## Onboarding Flow (14 Screens)

14-screen onboarding fully native SwiftUI implementation.

| Screen | View | Description |
|--------|------|-------------|
| 0 | `WelcomePage` | Teal bg, FloatingIconRing, CharacterView + dialog, CTA "I'm Ready!" |
| 1 | `FeatureCalendarPage` | 3 staggered DialogBubbles, bouncing arrows |
| 2 | `FeatureFocusPage` | BeforeAfterCard (tap-to-flip), blue-monster |
| 3 | `TextAnimationPage` | Dark bg, 7-line sequential text animation, tap to continue |
| 4 | `PersonalizationPage` | Theme picker (ThemePreviewCard) + Avatar selector |
| 5-12 | `QuestionnairePage(questionIndex:)` | Data-driven from OnboardingQuestions (8 questions) |
| 13 | `SignUpPage` | Google Sign In + Apple/Email placeholders |

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
- 5 stages: Baby -> Child -> Teen -> Adult -> Elder
- 5 moods: Happy, Excited, Focused, Sleepy, Missing You
- 4 scenes: Indoor, Outdoor, Night, Work

## AI Companion Text System (Inku Paradigm)

`CompanionTextService` generates personalized text (greetings, summaries, encouragement, etc.) using a two-tier approach:

1. **OpenAI path** (when API key configured): Builds `AIContext` from `UserProfile` (companionStyle, workType, goals) + app state, calls `OpenAIService.generateCompanionText()` with style-aware prompts (`companion`, `challenger`, `corporate`, `dramatic`, `genZ`, `slacker`), saves `AIInteraction` to `LocalStorage` for memory
2. **Local fallback** (no key or API failure): Returns from hardcoded template arrays (original behavior)

**Inku Paradigm**: The AI companion is an emotional value provider, NOT a productivity coach. It must never give advice, task breakdowns, or productivity tips. It only provides support, encouragement, sarcasm, or emotional reactions matching its personality. Output is capped at 60 characters.

**Prompt architecture (3 layers):**
- **Layer 1 - Persona**: `CompanionStyle` defines tone (warm, sarcastic, corporate, dramatic, chaotic, lazy)
- **Layer 2 - Context**: `<user_state>` (focus time, energy blocks, completion %, streak, petMood) + `<narrative_memory>` (episodic events)
- **Layer 3 - Rules**: Global constraints override all above (no advice, 60 char max, show don't tell)

Key flow: `DayPackGenerator` -> `CompanionTextService` -> `OpenAIService` (optional) -> `LocalStorage` (AI interactions)

### Home Companion Presentation Flow

- Homepage copy is owned by `AppState.currentHaiku`, `AppState.currentPetDialogue`, and `AppState.homeCompanionDisplayMode`.
- `AppState.refreshHomeCompanionPresentation()` is the single entry point for deciding what `HaikuSectionView` should render.
- The first visible Home presentation on a calendar day shows the daily haiku. After that day has been marked as shown, Home falls back to the shared pet dialogue path.
- Persist `LocalStorage.lastHomeHaikuShownDate` only after the haiku load finishes; do not mark the day as consumed before the async load completes.
- `LocalStorage.shared_companion_dialogue.json` caches the shared pet dialogue by date + fingerprint so repeated renders reuse the same message until the underlying Home state changes.
- `HomeView` should refresh the presentation when the scene returns to `.active`; do not rely on `onDisappear` to force mode switching across day boundaries.
- `PromptDebuggerView` must use `CompanionTextService.previewSharedPetDialogue()` so debugger output never pollutes production `AIInteraction` history or reminder memory.

- `TaskDehydrationService` decomposes tasks into `MicroAction` (What/When/Why) via `OpenAIService.dehydrateTask()`, with 24h cache in `LocalStorage` and fallback to task title
- `SmartReminderService` evaluates 4 trigger conditions in priority order: deadline -> streakProtect -> idle -> gentleNudge, rate-limited to 30min intervals, sends via `BLEDataEncoder.encodeSmartReminder()` (0x13 command)
- `FocusSessionService.statistics` provides expanded metrics: `averageSessionMinutes`, `longestSessionMinutes`, `interruptionCount`, `peakFocusHour`, `focusTrendDirection` (compared to yesterday via date-keyed session storage)

- `BehaviorAnalyzer` is a pure `struct` that computes `UserBehaviorSummary` from tasks/streak data for prompt injection
- `TimeOfDay.current(at:)` is the shared time-of-day utility (defined on the `TimeOfDay` enum in `DayPackGenerator.swift`) - use this instead of manual hour switches
- `LocalStorage` uses generic `save<T>`/`load<T>` helpers for all JSON persistence - follow this pattern for new data types
- All `CompanionTextService` methods accept `userProfile: UserProfile = .default` so call sites can stay concise

## E-ink Hardware Integration

### Hardware Specs
- **Product form**: 4-inch / 7.3-inch two sizes
- **4-inch screen**: 400 x 600 pixels, E Ink Spectra 6, 4bpp full color (6 colors: Black, White, Yellow, Red, Blue, Green)
- **7.3-inch screen**: 800 x 480 pixels, E Ink Spectra 6, 4bpp full color (6 colors)
- **SoC**: ESP32-S3, Flash >= 16MB, PSRAM >= 2MB
- **RTC**: Built-in RTC for timekeeping when BLE disconnected
- **Interaction**: Power button + Encoder knob (rotary + press) + BLE to iOS App

### Hardware Docs
- `docs/硬件需求文档-Hardware-Requirements-Document.md` (v0.3): Hardware electrical requirements
- `docs/固件功能规格文档.md` (v1.3.0): Firmware functional specifications
- `docs/BLE通信协议规格文档.md` (v1.3.1): BLE communication protocol

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
| Sign in with Apple | Configured | `Config/Kirole.entitlements` |

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Outku** is an iOS companion app for an E-ink hardware device. It helps remote workers build habits through AI-powered pixel pet companionship and gamified task management.

- **Platform**: iOS 17.0+ (iPhone only)
- **Language**: Swift 6.1+ with strict concurrency
- **UI Framework**: SwiftUI with Model-View (MV) pattern - no ViewModels
- **Testing**: Swift Testing framework (`@Test`, `#expect`, `#require`)

## Build & Test Commands

When XcodeBuildMCP tools are available, prefer them over raw xcodebuild:

```bash
# Using XcodeBuildMCP (preferred)
# Set session defaults first, then use build_sim, test_sim, etc.

# Using xcodebuild directly - Simulator
xcodebuild -workspace Outku.xcworkspace -scheme Outku \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

xcodebuild -workspace Outku.xcworkspace -scheme Outku \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Real device build & deploy
xcodebuild -workspace Outku.xcworkspace -scheme Outku \
  -destination 'platform=iOS,id=<DEVICE_ID>' -allowProvisioningUpdates build

xcrun devicectl device install app --device <DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/Outku-*/Build/Products/Debug-iphoneos/Outku.app

# List devices
xcrun xctrace list devices

# Swift Package only
cd OutkuPackage && swift test
```

## Architecture

### Workspace + SPM Package Structure

```
outku3/
├── Outku.xcworkspace/          # Open this in Xcode
├── Outku/                      # App shell (minimal - just entry point)
│   └── OutkuApp.swift
├── OutkuPackage/               # ALL development happens here
│   ├── Package.swift
│   └── Sources/OutkuFeature/
│       ├── ContentView.swift   # Root view with environment injection
│       ├── State/AppState.swift
│       ├── Models/Models.swift
│       ├── Design/Theme.swift
│       ├── Core/               # Services (Auth, API, Storage, BLE)
│       └── Views/              # Home, Pet, Settings, Onboarding, Components
└── Config/
    ├── Shared.xcconfig         # Bundle ID, version, deployment target
    ├── Secrets.xcconfig        # API keys (git-ignored)
    ├── Outku.entitlements      # App capabilities
    └── supabase-schema.sql     # Database schema for Supabase
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
- Content scrolls independently below the fixed header

### Key Services

| Service | Purpose |
|---------|---------|
| `AuthManager` | Apple Sign In + Google Sign In |
| `EventKitService` | Apple Calendar & Reminders |
| `GoogleCalendarAPI` | Google Calendar sync |
| `GoogleTasksAPI` | Google Tasks sync |
| `OpenAIService` | Haiku generation (GPT-4o-mini) |
| `SupabaseService` | Cloud data persistence |
| `CloudKitService` | iCloud sync (lazy-loaded) |
| `BLEService` | E-ink device communication |

## Code Patterns

### SwiftUI State (MV Pattern)

```swift
struct MyView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        // Direct property access
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
- Use `actor` for shared mutable state
- Use `.task` modifier in views (auto-cancels on disappear)
- Never use `Task {}` in `onAppear`
- Ensure `Sendable` conformance for types crossing concurrency boundaries

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

### Backend Services Status

| Service | Status | Config Location |
|---------|--------|-----------------|
| Google Sign In | ✅ Configured | `Config/Secrets.xcconfig` |
| Supabase | ✅ Configured | `Config/Secrets.xcconfig` |
| OpenAI | ⏳ Optional | User enters in Settings |
| Sign in with Apple | ⏳ Pending | Requires paid Apple Developer ($99/yr) |

### Secrets Configuration

Create `Config/Secrets.xcconfig` (git-ignored) with:
```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
GOOGLE_CLIENT_ID = xxx.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.xxx
SUPABASE_URL = https://xxx.supabase.co
SUPABASE_ANON_KEY = eyJxxx
```

### Database Schema

Run `Config/supabase-schema.sql` in Supabase SQL Editor to create tables:
- `pets` - Pet data (name, stage, mood, progress, etc.)
- `streaks` - User streak tracking
- `sync_state` - Sync tokens and status

## TODO / Pending Tasks

### Sign in with Apple (待配置)

需要付费版 Apple Developer Program ($99/年) 才能使用。配置步骤：

1. **Apple Developer Portal**:
   - Certificates, Identifiers & Profiles → Identifiers
   - 选择 App ID (`com.outku.app`)
   - 启用 "Sign in with Apple" capability

2. **Xcode**:
   - Signing & Capabilities → 添加 "Sign in with Apple"

3. **Config/Outku.entitlements** - 取消注释：
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array>
       <string>Default</string>
   </array>
   ```

4. **Supabase Dashboard**:
   - Authentication → Providers → Apple → 启用

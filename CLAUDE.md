# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Outku** is an iOS companion app for an E-ink hardware device. It helps remote workers build habits through AI-powered pixel pet companionship and gamified task management. The pet grows and evolves based on task completion, creating emotional motivation for productivity.

- **Platform**: iOS 17.0+ (iPhone only for MVP)
- **Language**: Swift 6.1+ with strict concurrency
- **UI Framework**: SwiftUI with Model-View (MV) pattern - no ViewModels
- **Testing**: Swift Testing framework (`@Test`, `#expect`, `#require`)

## Build & Test Commands

```bash
# Build for simulator (via XcodeBuildMCP tools preferred)
xcodebuild -workspace Outku.xcworkspace -scheme Outku -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run all tests
xcodebuild -workspace Outku.xcworkspace -scheme Outku -destination 'platform=iOS Simulator,name=iPhone 16' test

# Test Swift Package only
cd OutkuPackage && swift test

# Clean build
xcodebuild -workspace Outku.xcworkspace -scheme Outku clean
```

When XcodeBuildMCP tools are available, prefer using `build_sim_name_ws`, `test_sim_name_ws`, etc. over raw xcodebuild commands.

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
│       ├── ContentView.swift   # Root view with tab navigation
│       ├── State/AppState.swift # Global @Observable state singleton
│       ├── Models/Models.swift  # All data models (Pet, Task, Event, etc.)
│       ├── Design/Theme.swift   # Theme system with 5 color themes
│       └── Views/
│           ├── Home/           # Timeline view with events & haiku
│           ├── Pet/            # Task management & pet display
│           ├── Settings/       # Integrations & theme picker
│           ├── Onboarding/     # Story-driven intro flow
│           └── Components/     # Reusable UI (PixelPetView, etc.)
└── Config/
    ├── Shared.xcconfig         # Bundle ID, version, deployment target
    └── Outku.entitlements      # App capabilities (edit directly)
```

### State Management

- **AppState**: Singleton `@Observable` class holding all app state (pet, tasks, events, navigation)
- **ThemeManager**: Singleton managing current theme colors
- Both injected via `.environment()` from ContentView
- Views access via `@Environment(AppState.self)` and `@Environment(ThemeManager.self)`

### Key Models

| Model | Purpose |
|-------|---------|
| `Pet` | Name, stage, progress, stats (weight/height/tail), form (cat/dog/bunny/bird/dragon) |
| `TaskItem` | Title, completion status, due date, source, priority |
| `CalendarEvent` | Title, time range, source, participants, description |
| `Streak` | Current/longest streak tracking |
| `TaskStatistics` | Completion stats for today/week/month |

### Navigation

Tab-based navigation via `AppState.selectedTab` (enum: `.home`, `.pet`, `.settings`). No TabView - custom header buttons switch tabs.

## Code Patterns

### SwiftUI State (MV Pattern)

```swift
// View with environment access
struct MyView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        // Use appState.property directly
        // Use themeManager.colors.background, etc.
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

## Theme System

5 fixed themes: Cream (default), Sage, Lavender, Peach, Sky. Each provides:
- `background`, `cardBackground`, `primaryText`, `secondaryText`
- `accent`, `timeline`, `sunrise`, `sunset`
- `taskComplete`, `streakActive`

Access via `themeManager.colors.propertyName`.

## Future Integrations (Not Yet Implemented)

- Apple Calendar/Reminders (EventKit)
- Todoist API
- CoreBluetooth for E-ink device

## MVP Configuration Checklist

Before running the app, configure the following:

### 1. Google Sign In
Add to `Outku/Info.plist`:
```xml
<key>GIDClientID</key>
<string>YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_GOOGLE_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

### 2. Supabase
Edit `OutkuPackage/Sources/OutkuFeature/Core/Storage/SupabaseClient.swift`:
```swift
private let supabaseURL = "https://YOUR_PROJECT.supabase.co"
private let supabaseKey = "YOUR_ANON_KEY"
```

Database tables needed:
- `pets` (user_id, name, pronouns, adventures_count, age, status, mood, scene, stage, progress, weight, height, tail_length, current_form, last_interaction)
- `streaks` (user_id, current_streak, longest_streak, last_active_date)
- `sync_state` (user_id, last_sync_time, calendar_sync_token, tasks_sync_token, pending_changes, status)

### 3. OpenAI
Edit `OutkuPackage/Sources/OutkuFeature/Core/Network/OpenAIService.swift`:
```swift
private var apiKey: String = "YOUR_OPENAI_API_KEY"
```

Or call `OpenAIService.shared.configure(apiKey:)` at app launch.

### 4. Sign in with Apple
Add capability in Xcode:
1. Select Outku target → Signing & Capabilities
2. Click "+ Capability" → Add "Sign in with Apple"

Or edit `Config/Outku.entitlements`:
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

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

## Context7 Library IDs

When using Context7 MCP for documentation:
- Swift/Apple: `/websites/developer_apple`
- SwiftUI patterns: `/pointfreeco/swift-composable-architecture` (for reference)
- Swift Navigation: `/pointfreeco/swift--navigation`

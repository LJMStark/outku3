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
# Build for simulator (use available simulator name)
xcodebuild -workspace Outku.xcworkspace -scheme Outku -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild -workspace Outku.xcworkspace -scheme Outku -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Test Swift Package only
cd OutkuPackage && swift test

# Clean build
xcodebuild -workspace Outku.xcworkspace -scheme Outku clean

# List available simulators
xcrun simctl list devices available
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

- Todoist API

## Implemented Features

### Core Services
- **AuthManager**: Apple Sign In + Google Sign In authentication
- **EventKitService**: Apple Calendar & Reminders integration
- **GoogleCalendarAPI**: Google Calendar read-only sync
- **GoogleTasksAPI**: Google Tasks bidirectional sync
- **OpenAIService**: Haiku generation via GPT-4o-mini
- **SupabaseService**: Cloud data persistence
- **CloudKitService**: iCloud sync for user data
- **BLEService**: CoreBluetooth for E-ink device communication
- **SoundService**: Audio feedback with AVFoundation
- **WidgetDataService**: iOS Widget data provider
- **PetStateService**: Pet mood/scene calculation
- **HaikuService**: Haiku generation orchestration

### Pet System
- 5 pet forms: Cat, Dog, Bunny, Bird, Dragon
- 5 evolution stages: Baby → Child → Teen → Adult → Elder
- 5 moods: Happy, Excited, Focused, Sleepy, Missing You
- 4 scenes: Indoor, Outdoor, Night, Work
- Mood-specific animations (Zzz, sparkles, question marks, focus rings)

## MVP Configuration Checklist

Before running the app, configure the following:

### 1. Google Sign In
Create a project in [Google Cloud Console](https://console.cloud.google.com/):
1. Enable Google Calendar API and Google Tasks API
2. Create OAuth 2.0 credentials (iOS app type)
3. Add your Bundle ID: `com.outku.app` (or your custom ID)

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
Create a project at [Supabase](https://supabase.com/):

Edit `OutkuPackage/Sources/OutkuFeature/Core/Storage/SupabaseClient.swift`:
```swift
private let supabaseURL = "https://YOUR_PROJECT.supabase.co"
private let supabaseKey = "YOUR_ANON_KEY"
```

Run the following SQL to create tables:
```sql
-- Users table (handled by Supabase Auth)

-- Pets table
CREATE TABLE pets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT 'Baby Waffle',
    pronouns TEXT DEFAULT 'They/Them',
    adventures_count INTEGER DEFAULT 0,
    age INTEGER DEFAULT 1,
    status TEXT DEFAULT 'Happy',
    mood TEXT DEFAULT 'Happy',
    scene TEXT DEFAULT 'Indoor',
    stage TEXT DEFAULT 'Baby',
    progress FLOAT DEFAULT 0.0,
    weight FLOAT DEFAULT 50,
    height FLOAT DEFAULT 5,
    tail_length FLOAT DEFAULT 2,
    current_form TEXT DEFAULT 'Cat',
    last_interaction TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Streaks table
CREATE TABLE streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_active_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Sync state table
CREATE TABLE sync_state (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    last_sync_time TIMESTAMPTZ,
    calendar_sync_token TEXT,
    tasks_sync_token TEXT,
    pending_changes JSONB DEFAULT '[]',
    status TEXT DEFAULT 'synced',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Enable Row Level Security
ALTER TABLE pets ENABLE ROW LEVEL SECURITY;
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_state ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can manage their own pets"
    ON pets FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own streaks"
    ON streaks FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own sync state"
    ON sync_state FOR ALL USING (auth.uid() = user_id);
```

### 3. OpenAI
Get an API key from [OpenAI Platform](https://platform.openai.com/):

Edit `OutkuPackage/Sources/OutkuFeature/Core/Network/OpenAIService.swift`:
```swift
private var apiKey: String = "sk-YOUR_OPENAI_API_KEY"
```

Or configure at runtime:
```swift
await OpenAIService.shared.configure(apiKey: "sk-YOUR_OPENAI_API_KEY")
```

**Note**: The app uses `gpt-4o-mini` model for cost-effective Haiku generation.

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

### 5. EventKit (Calendar & Reminders)
Add to `Outku/Info.plist`:
```xml
<key>NSCalendarsUsageDescription</key>
<string>Outku needs access to your calendar to display events and help your pet track your schedule.</string>
<key>NSRemindersUsageDescription</key>
<string>Outku needs access to your reminders to sync tasks with your pet companion.</string>
```

### 6. CloudKit (Optional)
For iCloud sync, add capability in Xcode:
1. Select Outku target → Signing & Capabilities
2. Click "+ Capability" → Add "iCloud"
3. Enable "CloudKit" and create a container

### 7. Bluetooth (E-ink Device)
Add to `Outku/Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Outku needs Bluetooth to connect to your E-ink companion device.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Outku needs Bluetooth to communicate with your E-ink device.</string>
```

## Deployment Checklist

### Before App Store Submission
1. [ ] Replace all placeholder API keys with production values
2. [ ] Configure App Store Connect with app metadata
3. [ ] Set up Supabase production environment
4. [ ] Enable Apple Sign In in App Store Connect
5. [ ] Configure Google OAuth consent screen for production
6. [ ] Test all integrations in TestFlight
7. [ ] Verify privacy policy and terms of service URLs
8. [ ] Check all Info.plist usage descriptions are accurate

### Environment Variables (Recommended for Production)
Instead of hardcoding API keys, use environment variables or a secure configuration:

```swift
// Example: Using xcconfig for different environments
// Debug.xcconfig
OPENAI_API_KEY = sk-dev-key
SUPABASE_URL = https://dev-project.supabase.co
SUPABASE_KEY = dev-anon-key

// Release.xcconfig
OPENAI_API_KEY = sk-prod-key
SUPABASE_URL = https://prod-project.supabase.co
SUPABASE_KEY = prod-anon-key
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

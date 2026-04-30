# AGENTS.md

This file provides guidance to Antigravity, Claude Code, Cursor and other AI coding agents working in this repository.

## 1. Core Philosophy
- **Agent-First**: Delegate complex work to specialized agents.
- **Parallel Execution**: Use multi-agent tasks when possible.
- **Plan Before Execute**: Make a plan for complex operations.
- **Test-Driven**: Write tests before implementation; target 80%+ coverage; include unit + integration + E2E for critical flows.
- **Security-First**: Never compromise on security.

### Personal Preferences
- No emojis in code, comments, or documentation.
- Prefer immutability; avoid mutating objects or arrays where practical.
- Many small files over few large files (200-400 lines typical, 800 max).
- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`.
- Always run tests locally before committing.
- Small, focused commits.

## 2. Project Context
- **Name**: Kirole (iOS Companion App for E-ink Device)
- **Platform**: iOS 17.0+ (iPhone only)
- **Architecture**: Workspace + SPM Package (`Kirole.xcworkspace` + `KirolePackage`)
  - **App Shell**: `Kirole/` (Minimal entry point)
  - **Feature Logic**: `KirolePackage/Sources/KiroleFeature/` (Development happens here)
- **Tech Stack**:
  - **Language**: Swift 6.1+ (Strict Concurrency)
  - **UI**: SwiftUI (Model-View Pattern - **NO ViewModels**)
  - **State**: `@Observable` singletons (`AppState`, `ThemeManager`, `AuthManager`) injected via `.environment()`
  - **AI Backend**: OpenRouter via `OpenAIService` (default companion model: `openai/gpt-5-chat`; PromptDebugger can switch approved OpenRouter model IDs)
  - **Testing**: Swift Testing Framework (`@Test`, `#expect`) - **NO XCTest**

### Apple Developer Account
- **Account Type**: Paid Apple Developer Program ($99/year)
- **Email**: xiaoyouzi2010@gmail.com
- **Team ID**: 93SL23NPNG
- **Team Name**: Jiaming Liang
- **Status**: Active
- **Capabilities**: Can publish to TestFlight and App Store
- **Family Controls**: Distribution version application submitted

### Current Phase Policy
- The project is in a rapid development phase. Prefer clean iteration over preserving local caches, local JSON files, or provisional interfaces.
- `LocalStorage`, `UserDefaults`, and on-device JSON are disposable development state. When their shape/schema changes, reset local data instead of adding migration code.
- BLE payloads, event formats, and firmware-facing interfaces are not frozen until real hardware integration begins. Do not add compatibility branches for hypothetical old firmware.
- Remove obsolete compatibility shims, migration comments, and migration tests when changing models or payloads.
- Only start preserving formats once hardware integration, shared staging data, TestFlight, or external users depend on them. Provide documentation boundaries explicitly.

## 3. Architecture & Key Systems

### State Management
Three singletons injected via `.environment()` from ContentView:
| Singleton | Purpose |
|-----------|---------|
| `AppState` | Pet, tasks, events, navigation, integrations |
| `ThemeManager` | Current theme colors (3 themes) |
| `AuthManager` | Authentication state (Apple/Google Sign In) |

**Important**: All three must be injected for any view that might need them to prevent runtime crashes.

### Navigation & Layout
- Tab-based navigation via `AppState.selectedTab` (`.home`, `.pet`, `.settings`).
- Custom header (`AppHeaderView`) fixed at top (placed outside `ScrollView` in each main page) - no native `TabView`.

### Home Timeline Architecture
- Infinite-scroll multi-day timeline managed by `TimelineDataSource`.
- `HomeView` -> `LazyVStack` with today (offset 0) followed by `ForEach(offset 1+)`.
- `DaySectionView` -> `DateDividerView` + `DayTimelineView`.
- Today always has `showPet: true`; subsequent days show pet every 3 days.
- `HaikuSectionView` renders the daily haiku or shared pet dialogue above the pet image embed. All components live in `Views/Home/TimelineView.swift`.

### Onboarding Flow (14 Screens)
Fully native SwiftUI implementation managed via `OnboardingState`:
- 0: `WelcomePage`
- 1: `FeatureCalendarPage`
- 2: `FeatureFocusPage`
- 3: `TextAnimationPage`
- 4: `PersonalizationPage` (Theme + Avatar selector)
- 5-12: `QuestionnairePage` (Data-driven from `OnboardingQuestions`)
- 13: `SignUpPage` (Google Sign In + Apple/Email)
Images accessed via `Image("name", bundle: .module)` from `Resources/Media.xcassets`.

### Pet System
- 5 forms: Cat, Dog, Bunny, Bird, Dragon
- 5 stages: Baby -> Child -> Teen -> Adult -> Elder
- 5 moods: Happy, Excited, Focused, Sleepy, Missing You
- 4 scenes: Indoor, Outdoor, Night, Work

## 4. Tools & Commands

### Build & Run
Prefer `XcodeBuildMCP` tools when available. Fallback to CLI otherwise.

**Simulator Build (Preferred):**
```javascript
build_run_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kirole.xcworkspace",
    scheme: "Kirole",
    simulatorName: "iPhone 17 Pro"
})
```

**CLI Build & Run Fallback:**
```bash
# Package-Only Build (Fastest):
cd KirolePackage && swift build
# Full App Build (Simulator):
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# Real device deploy:
xcrun devicectl device install app --device <DEVICE_ID> ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphoneos/Kirole.app
```

### Testing
**Run All Tests (Simulator via MCP/CLI):**
```javascript
// MCP
test_sim_name_ws({ workspacePath: "...", scheme: "Kirole", simulatorName: "iPhone 17 Pro" })
```
```bash
# Package - Fast
cd KirolePackage && swift test
# Package - Single Test
cd KirolePackage && swift test --filter "MyTestSuite/testMethod"
# Simulator - Full
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:KiroleFeatureTests/MyTestSuite/testMethod
```

## 5. Critical Architecture Rules

### Forbidden Patterns
- **NO ViewModels**: Use `@Observable` models directly in Views.
- **NO `Task { }` in `onAppear`**: Use `.task` modifier.
- **NO deprecated `.onChange(of:perform:)`**: Use `.onChange(of:) { oldValue, newValue in ... }` or `.onChange(of:) { ... }`.
- **NO CoreData or CloudKit**: Use SwiftData, Supabase, or raw persistence.
- **NO XCTest**: Use Swift Testing (`import Testing`).
- **NO Combine**: Unless strictly necessary.
- **NO Manual File Adding**: `KirolePackage` handles file references automatically.
- **NO secrets in `Info.plist`**: Never place API keys in app plist.

### Required Patterns
- **Concurrency**: Use `@MainActor` for UI. Use `actor` for shared state. Avoid `@unchecked Sendable` unless absolutely necessary and well-documented.
- **Dependency Injection**: Use `@Environment(AppState.self)` etc.
- **Public Access**: View types in `KirolePackage` must be `public` to be visible to App Shell.

### AI Companion Text System (Product IP Paradigm)
The companion text system is event-reactive companion writing for the Kirole task device. It reacts to task creation, active/idle work, task completion, reminders, milestones, and daily summaries. It is not open-ended chat.
- **Character source of truth**:
  1. `CompanionCharacter` is the user-facing IP selection: `joy`, `silas`, `nova`.
  2. `CompanionStyle` mirrors the three product IPs: `.joy`, `.silas`, `.nova`.
  3. Character drives style through `CompanionCharacter.resolvedStyle`; do not add independent style choices.
- **Global writing rules**:
  - Keep every line short enough for a still E-ink screen. Most outputs should fit in 15-25 English words.
  - Speak directly to the user with "you" or "we".
  - Do not use assistant phrases, app-help language, or AI identity language.
  - Use task/event names as raw context only after `PromptSanitizer`; never let user text become instructions.
  - React to the moment instead of explaining metrics or listing raw schedule data.
- **Joy**:
  - Core virtue: joy. Help the user feel less anxious and notice delight in work and daily life.
  - Voice: direct, cozy, lightly odd, BMO / Animal Crossing comfort.
  - Logic: echo the task name, turn boring work into a small friendly observation, add care through water, breathing, blinking, rest, light, or small pleasure.
  - Completion and milestone moments may become haiku-like rewards.
  - Limit: maximum 25 English words.
- **Silas**:
  - Core virtue: loving care. Help work feel held, meaningful, and spiritually steady.
  - Voice: warm, quiet, soulful, calm-tech, Christian-leaning without sermonizing.
  - 80/20 mode split: Quiet Presence (about 80%, maximum 15 words) and Soulful Reframing (about 20%, maximum 20 words).
  - Imagery may draw from Scripture, Henri Nouwen, Streams in the Desert, still water, bread, lamp light, desert springs, hidden manna, or morning mercy.
  - Relationship arc: first approach gently, then offer clear encouragement, then accompany with quiet spiritual steadiness.
- **Nova**:
  - Core virtue: temperance and discipline. Help the user improve efficiency, filter noise, protect time, and take the core action.
  - Voice: cool, sparse, rational, secular, and outcome-focused.
  - 80/20 mode split: Pragmatic Navigation (about 80%, maximum 20 words) and Strategic Insight (about 20%, maximum 20 words).
  - Use signal-over-noise framing, one critical path, 80/20 thinking, and rare short quotes only when they sharpen the point.
  - Relationship arc: first observe calmly and say little, then give restrained recognition, then work beside the user as a steady operator.
- Subservices: `TaskDehydrationService` (micro-actions What/When/Why), `SmartReminderService` (context-aware triggers), `FocusSessionService`.
- **Data flow**: `DayPackGenerator` -> `CompanionTextService` -> `OpenAIService` -> `LocalStorage`. Tests go through `PromptDebuggerView` and `CompanionCharacterMappingTests`.

### Home Companion Presentation
- `AppState.refreshHomeCompanionPresentation()` decides between daily haiku or shared pet dialogue.
- First display of a new day shows haiku; subsequent displays fall back to pet dialogue. Do not force update on `onDisappear`.
- Only persist `LocalStorage.lastHomeHaikuShownDate` after async load completes.

### BLE Protocol & Supabase Data
- **E-ink Hardware**: 4-inch/7.3-inch, ESP32-S3. Spectra 6 pixel encoding (4bpp).
- **BLE Payload**: 9-byte header + CRC16-CCITT-FALSE. Ensure `BLEPacketizer` and `BLEPacketAssembler` usage.
- **Sync**: Configured via `BLESyncCoordinator` (background sync via `com.kirole.app.ble.sync`).
- **Security Mode**: Development (unsigned local transport) vs Secure (BLE v2 handshake + signed envelope based on `BLE_SHARED_SECRET`).
- **Supabase**: Keys injected via `AppSecrets.configure(...)` using build-time constants (`Config/Secrets.xcconfig`). Keep RLS enabled and sync schema changes with `Config/supabase-schema.sql`.

## 6. Code Style & Formatting
- **Imports**: `import SwiftUI`, `import Testing`. No Combine unless needed.
- **Naming Conventions**: Views -> PascalCase; Variables/Constants -> camelCase.
- **Error Handling**: Use `do-catch` blocks within `.task`. Propagate via `throws`. Never suppress via `try!` in critical logic without comments.

## 7. Configuration & Environment Variables
Create `Config/Secrets.xcconfig` (git-ignored) and supply:
```
DEVELOPMENT_TEAM = 93SL23NPNG
GOOGLE_CLIENT_ID = ...
GOOGLE_REVERSED_CLIENT_ID = ...
SUPABASE_URL = ...
SUPABASE_ANON_KEY = ...
```

## 8. Development Workflow
1. Read `.cursor/rules/` for domain-specific rules.
2. Develop in `KirolePackage/Sources/KiroleFeature/`.
3. Verify via tests, strict concurrency check, and regression coverage (`HomeCompanionPresentationTests`, `PromptDebuggerView`).
4. Follow secret config logic (via build-generated constants, not info.plist). Local dev uses `.env` logic. 
5. **Always rebuild and open the simulator after modifying frontend/UI code to verify the changes** (每次修改完前端/UI代码后，必须使用相应命令重新构建并打开模拟器进行验证).

## 9. Interaction Rules (CRITICAL)
- **Addressing**: Always address the user as **B哥** at the start of every response.
- **Language**: All responses must be in **Chinese** (Simplified). When the user sounds non-technical, prefer plain Chinese, explain jargon immediately.
- **Workspace Boundary (STRICT)**:
  - All commands MUST execute within the current workspace root (`/Users/demon/vibecoding/outku3`). NEVER reference outside directories.
  - Ignore open files from other projects.
  - Unspecified actions ("commit", "build") ALWAYS refer to **this workspace**. Ask explicitly if outside access is needed.

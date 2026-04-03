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
  - **AI Backend**: OpenRouter (`openai/gpt-4o-mini`) via `OpenAIService`
  - **Testing**: Swift Testing Framework (`@Test`, `#expect`) - **NO XCTest**

## 3. Tools & Commands

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

**CLI Build (Fallback):**
```bash
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

**Package-Only Build (Fastest):**
```bash
cd KirolePackage && swift build
```

### Testing
**Run All Tests (Simulator):**
```javascript
test_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kirole.xcworkspace",
    scheme: "Kirole",
    simulatorName: "iPhone 17 Pro"
})
```

**Run All Tests (Package - Fast):**
```bash
cd KirolePackage && swift test
```

**Run Single Test (Package - Fast):**
```bash
cd KirolePackage && swift test --filter "MyTestSuite/testMethod"
```

**Run Single Test (Simulator - Full):**
```bash
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:KiroleFeatureTests/MyTestSuite/testMethod
```

## 4. Critical Architecture Rules

### Forbidden Patterns
- **NO ViewModels**: Use `@Observable` models directly in Views.
- **NO `Task { }` in `onAppear`**: Use `.task` modifier.
- **NO deprecated `.onChange(of:perform:)`**: Use `.onChange(of:) { oldValue, newValue in ... }` or `.onChange(of:) { ... }`.
- **NO CoreData**: Use SwiftData or raw persistence.
- **NO XCTest**: Use Swift Testing (`import Testing`).
- **NO Manual File Adding**: `KirolePackage` handles file references automatically.

### Required Patterns
- **Concurrency**: Use `@MainActor` for UI. Use `actor` for shared state.
- **Navigation**: Custom `AppHeaderView` fixed at top (outside `ScrollView`).
- **Dependency Injection**:
  ```swift
  @Environment(AppState.self) private var appState
  @Environment(ThemeManager.self) private var theme
  ```
- **Public Access**: View types in `KirolePackage` must be `public` to be visible to App Shell.
  ```swift
  public struct MyView: View {
      public init() {} // Required public init
      public var body: some View { ... }
  }
  ```

### Home Companion Presentation
- `AppState.refreshHomeCompanionPresentation()` is the single entry point for deciding whether Home shows the daily haiku or the shared pet dialogue.
- `HaikuSectionView` renders from `currentHaiku`, `currentPetDialogue`, and `homeCompanionDisplayMode`; keep those three values consistent.
- First display of a new calendar day always shows the daily haiku; subsequent displays fall back to pet dialogue.
- Never force Home into `petDialogue` from `onDisappear`; refresh presentation on re-entry / scene activation instead so day rollover still shows the next day's haiku.
- Only persist `LocalStorage.lastHomeHaikuShownDate` after the haiku has actually finished loading.
- Prompt debugger output must go through a preview-only path (`CompanionTextService.previewSharedPetDialogue()`) and must not be written into production `AIInteraction` history.

### AI Companion Text System (Inku Paradigm)
The AI companion is an **emotional value provider**, NOT a productivity coach or life planner.

**Architecture (3-layer prompt assembly in `OpenAIService.swift`):**
1. **Persona Layer** (`CompanionStyle`): 6 personality presets (companion, challenger, corporate, dramatic, genZ, slacker). Defines tone/vibe only.
2. **Context Layer** (`<user_state>` + `<narrative_memory>`): Dynamic data injection (focus time, energy blocks, completion rate, streak, petMood, episodic memories).
3. **Rules Layer** (`<rules>`): Global constraints that override everything above.

**Global Rules (enforced on ALL personalities):**
- `EMOTIONAL VALUE ONLY`: No advice, no productivity tips, no task guidance.
- `MAXIMUM 60 characters`: Extremely brief output.
- `SHOW, DON'T TELL`: React via mood/behavior, not by reciting stats.
- Never act like a reporting analytics device.

**When modifying AI prompts:**
- Never add instructions that encourage the AI to give advice, suggestions, or task breakdowns.
- Keep input data rich (so the AI "understands" the user), but output constraints strict (so it only emotes).
- All persona changes must be tested through `PromptDebuggerView` to verify compliance with the Inku paradigm.

**Data flow:** `CompanionTextService` -> `OpenAIService.generateCompanionText()` -> OpenRouter API -> `LocalStorage` (AI interactions)

### BLE Protocol & Sync (Hardware)
- Always send BLE payloads through `BLEPacketizer` and assemble via `BLEPacketAssembler` (9-byte header + CRC16-CCITT-FALSE).
- Use `BLESyncCoordinator` for scheduled sync (08:00-23:00 hourly; 23:00-08:00 every 4 hours; 30s window).
- Gate DayPack refresh with `DayPack.stableFingerprint()` and `LocalStorage.lastDayPackHash`.
- Background sync uses `BLEBackgroundSyncScheduler` and BGTask id `com.kirole.app.ble.sync`.
- BLE link runs in two modes:
  - **Compatibility Mode (MVP default)**: when `BLE_SHARED_SECRET` is not configured, legacy plaintext protocol is allowed for hardware integration.
  - **Secure Mode**: when `BLE_SHARED_SECRET` is configured, enforce BLE v2 handshake + signed secure envelope + replay protection.
- Settings UI must expose current BLE mode using `BLEService.configuredSecurityMode` so firmware/App teams can verify integration state.

### Supabase Data & Security
- Client runtime config must be injected via `AppSecrets.configure(...)` from App shell (`KiroleApp`) using build-time constants.
- `Info.plist` must not contain `OPENROUTER_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, or `BLE_SHARED_SECRET`.
- Build-time secret sources (`Config/Secrets.xcconfig`, env vars, generated `Kirole/BuildSecrets.generated.swift`) must never commit real secrets.
- Never use or expose `service_role` keys in iOS code, app bundles, repo files, or logs.
- Keep RLS enabled on all business tables and scope policies to `auth.uid()`.
- Any Supabase model field change in Swift code must update `Config/supabase-schema.sql` in the same patch.
- Include backward-compatible SQL migration for existing databases (for example: `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`).
- Apply schema/migrations before releasing app code that writes new fields.

## 5. Code Style & Formatting

### Imports
```swift
import SwiftUI
import Testing // For test files
// Do NOT import Combine unless strictly necessary
```

### Naming Conventions
- **Views**: PascalCase (e.g., `PetStatusView`)
- **Variables**: camelCase (e.g., `currentMood`)
- **Constants**: camelCase (e.g., `maxRetries`)

### Error Handling
- Use `do-catch` blocks within `.task`.
- Propagate errors using `throws`.
- **Never** suppress errors with `try?` or `try!` in critical logic without comments.

## 6. Development Workflow

1.  **Check Rules**: Read `.cursor/rules/` for specific domain rules (Concurrency, SwiftUI, Testing).
2.  **Implementation**:
    -   Modify/Create files in `KirolePackage/Sources/KiroleFeature/`.
    -   Ensure `public` modifiers if file is referenced by App Shell.
3.  **Verification**:
    -   Run tests via `swift test` (fast) or `xcodebuild` (thorough).
    -   Fix concurrency warnings (Strict Concurrency is ENABLED).
    -   If you touch Home companion presentation behavior, update/add focused regression coverage in `KirolePackage/Tests/KiroleFeatureTests/HomeCompanionPresentationTests.swift`.
    -   If you touch AI companion prompts, test through `PromptDebuggerView` to verify no advice/coaching leaks through.
4.  **Configuration**:
    -   App shell injects secrets via `AppSecrets.configure(...)` (build-generated constants; no runtime `Info.plist` reads).
    -   `Kirole/BuildSecrets.generated.swift` is generated by build script and should not contain real secrets in git.
    -   Capabilities go in `Config/Kirole.entitlements`.

## 7. Reference Files
- **Claude Code Guide**: `CLAUDE.md` (references this file)
- **Cursor Rules**: `.cursor/rules/*.mdc`
- **Copilot Rules**: `.github/copilot-instructions.md`

## 8. Interaction Rules (CRITICAL)
- **Addressing**: Always address the user as **B哥** at the start of every response.
- **Language**: All responses must be in **Chinese** (Simplified).

# AGENTS.md - Kirole Project Guidelines

This file provides essential context, commands, and rules for AI agents working on the Kirole iOS codebase.

## 1. Core Philosophy
- **Agent-First**: Delegate complex work to specialized agents.
- **Parallel Execution**: Use multi-agent tasks when possible.
- **Plan Before Execute**: Make a plan for complex operations.
- **Test-Driven**: Write tests before implementation; target 80%+ coverage; include unit + integration + E2E for critical flows.
- **Security-First**: Never compromise on security.

### Personal Preferences
- No emojis in code, comments, or documentation.
- Prefer immutability; avoid mutating objects or arrays where practical.
- Many small files over few large files (200–400 lines typical, 800 max).
- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`.
- Always run tests locally before committing.
- Small, focused commits.

## 2. Project Context
- **Name**: Kirole (iOS Companion App for E-ink Device)
- **Architecture**: Workspace + SPM Package (`Kirole.xcworkspace` + `KirolePackage`)
  - **App Shell**: `Kirole/` (Minimal entry point)
  - **Feature Logic**: `KirolePackage/Sources/KiroleFeature/` (Development happens here)
- **Tech Stack**:
  - **Language**: Swift 6.1+ (Strict Concurrency)
  - **UI**: SwiftUI (Model-View Pattern - **NO ViewModels**)
  - **State**: `@Observable` singletons (`AppState`, `ThemeManager`, `AuthManager`) injected via `.environment()`
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

### Testing
**Run All Tests (Simulator):**
```javascript
test_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kirole.xcworkspace",
    scheme: "Kirole",
    simulatorName: "iPhone 17 Pro"
})
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

### ❌ Forbidden Patterns
- **NO ViewModels**: Use `@Observable` models directly in Views.
- **NO `Task { }` in `onAppear`**: Use `.task` modifier.
- **NO CoreData**: Use SwiftData or raw persistence.
- **NO XCTest**: Use Swift Testing (`import Testing`).
- **NO Manual File Adding**: `KirolePackage` handles file references automatically.

### ✅ Required Patterns
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

### BLE Protocol & Sync (Hardware)
- Always send BLE payloads through `BLEPacketizer` and assemble via `BLEPacketAssembler` (9-byte header + CRC16-CCITT-FALSE).
- Use `BLESyncCoordinator` for scheduled sync (08:00–23:00 hourly; 23:00–08:00 every 4 hours; 30s window).
- Gate DayPack refresh with `DayPack.stableFingerprint()` and `LocalStorage.lastDayPackHash`.
- Background sync uses `BLEBackgroundSyncScheduler` and BGTask id `com.kirole.app.ble.sync`.

### Supabase Data & Security
- Client-side configuration may only include `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- `Config/Secrets.xcconfig` must stay git-ignored and must never be committed.
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
4.  **Configuration**:
    -   Secrets go in `Config/Secrets.xcconfig`.
    -   Capabilities go in `Config/Kirole.entitlements`.

## 7. Reference Files
- **Primary Guide**: `CLAUDE.md` (Read this first)
- **Cursor Rules**: `.cursor/rules/*.mdc`
- **Copilot Rules**: `.github/copilot-instructions.md`

## 8. Interaction Rules (CRITICAL)
- **Addressing**: Always address the user as **B哥** at the start of every response.
- **Language**: All responses must be in **Chinese** (Simplified).

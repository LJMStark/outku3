# AGENTS.md - Kiro Project Guidelines

This file provides essential context, commands, and rules for AI agents working on the Kiro iOS codebase.

## 1. Project Context
- **Name**: Kiro (iOS Companion App for E-ink Device)
- **Architecture**: Workspace + SPM Package (`Kiro.xcworkspace` + `KiroPackage`)
  - **App Shell**: `Kiro/` (Minimal entry point)
  - **Feature Logic**: `KiroPackage/Sources/KiroFeature/` (Development happens here)
- **Tech Stack**:
  - **Language**: Swift 6.1+ (Strict Concurrency)
  - **UI**: SwiftUI (Model-View Pattern - **NO ViewModels**)
  - **State**: `@Observable` singletons (`AppState`, `ThemeManager`, `AuthManager`) injected via `.environment()`
  - **Testing**: Swift Testing Framework (`@Test`, `#expect`) - **NO XCTest**

## 2. Tools & Commands

### Build & Run
Prefer `XcodeBuildMCP` tools when available. Fallback to CLI otherwise.

**Simulator Build (Preferred):**
```javascript
build_run_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kiro.xcworkspace",
    scheme: "Kiro",
    simulatorName: "iPhone 17 Pro"
})
```

**CLI Build (Fallback):**
```bash
xcodebuild -workspace Kiro.xcworkspace -scheme Kiro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Testing
**Run All Tests (Simulator):**
```javascript
test_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kiro.xcworkspace",
    scheme: "Kiro",
    simulatorName: "iPhone 17 Pro"
})
```

**Run Single Test (Package - Fast):**
```bash
cd KiroPackage && swift test --filter "MyTestSuite/testMethod"
```

**Run Single Test (Simulator - Full):**
```bash
xcodebuild -workspace Kiro.xcworkspace -scheme Kiro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:KiroFeatureTests/MyTestSuite/testMethod
```

## 3. Critical Architecture Rules

### ❌ Forbidden Patterns
- **NO ViewModels**: Use `@Observable` models directly in Views.
- **NO `Task { }` in `onAppear`**: Use `.task` modifier.
- **NO CoreData**: Use SwiftData or raw persistence.
- **NO XCTest**: Use Swift Testing (`import Testing`).
- **NO Manual File Adding**: `KiroPackage` handles file references automatically.

### ✅ Required Patterns
- **Concurrency**: Use `@MainActor` for UI. Use `actor` for shared state.
- **Navigation**: Custom `AppHeaderView` fixed at top (outside `ScrollView`).
- **Dependency Injection**:
  ```swift
  @Environment(AppState.self) private var appState
  @Environment(ThemeManager.self) private var theme
  ```
- **Public Access**: View types in `KiroPackage` must be `public` to be visible to App Shell.
  ```swift
  public struct MyView: View {
      public init() {} // Required public init
      public var body: some View { ... }
  }
  ```

## 4. Code Style & Formatting

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

## 5. Development Workflow

1.  **Check Rules**: Read `.cursor/rules/` for specific domain rules (Concurrency, SwiftUI, Testing).
2.  **Implementation**:
    -   Modify/Create files in `KiroPackage/Sources/KiroFeature/`.
    -   Ensure `public` modifiers if file is referenced by App Shell.
3.  **Verification**:
    -   Run tests via `swift test` (fast) or `xcodebuild` (thorough).
    -   Fix concurrency warnings (Strict Concurrency is ENABLED).
4.  **Configuration**:
    -   Secrets go in `Config/Secrets.xcconfig`.
    -   Capabilities go in `Config/Kiro.entitlements`.

## 6. Reference Files
- **Primary Guide**: `CLAUDE.md` (Read this first)
- **Cursor Rules**: `.cursor/rules/*.mdc`
- **Copilot Rules**: `.github/copilot-instructions.md`

## 7. Interaction Rules (CRITICAL)
- **Addressing**: Always address the user as **B哥** at the start of every response.
- **Language**: All responses must be in **Chinese** (Simplified).


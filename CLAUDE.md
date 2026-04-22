# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The authoritative rules, architecture notes, and command reference live in `./AGENTS.md`.
Read it before any non-trivial change. `.cursor/rules/*.mdc` contains additional
Swift/SwiftUI/Testing/Concurrency guidance that applies here too.

## Interaction Rules
1. Every response must begin with **B哥**.
2. Respond in **Simplified Chinese**. For non-technical questions, keep language plain and explain jargon inline.
3. Treat `/Users/demon/vibecoding/outku3` as the strict workspace boundary. Unqualified requests ("build", "commit", "run tests") always refer to this repo.

## Development Rules
1. After any frontend / UI change, rebuild and launch the simulator to visually verify. Do not mark UI work complete without this check.
2. The project is in rapid iteration: `LocalStorage`, `UserDefaults`, on-device JSON, and BLE payload shapes are disposable. Prefer resetting local data over writing migration shims until hardware/TestFlight consumers exist (see AGENTS.md §2 "Current Phase Policy").

## Architecture at a Glance
- Workspace + SPM: `Kirole.xcworkspace` opens everything; app shell lives in `Kirole/`, all feature code in `KirolePackage/Sources/KiroleFeature/`. New code almost always belongs in the package.
- UI stack: SwiftUI with **Model-View only** — no ViewModels. State flows through three `@Observable` singletons injected at `ContentView`: `AppState`, `ThemeManager`, `AuthManager`. Any view that might read them needs all three in its environment.
- Key subsystems (detail in AGENTS.md §3): Timeline (`TimelineDataSource` + `HomeView`), 14-screen onboarding (`OnboardingState`), Pet system (5 forms × 5 stages × 5 moods × 4 scenes), Companion text pipeline (`DayPackGenerator` → `CompanionTextService` → `OpenAIService`), BLE sync (`BLEPacketizer`/`BLESyncCoordinator`), Supabase persistence.
- Views exposed from `KirolePackage` to the app shell must be `public`.

## Hard Constraints (do not violate)
- NO ViewModels, NO XCTest (use Swift Testing: `import Testing`, `@Test`, `#expect`), NO CoreData/CloudKit, NO Combine unless strictly required, NO `Task { }` inside `onAppear` (use `.task`).
- NO secrets in `Info.plist`. Secrets come from `Config/Secrets.xcconfig` (git-ignored) via `AppSecrets.configure(...)`.
- NO manual file adding to Xcode targets — `KirolePackage` uses buildable folders.
- Concurrency: `@MainActor` for UI, `actor` for shared state, avoid `@unchecked Sendable`.
- Accessibility: every interactive element needs `accessibilityLabel` and `accessibilityIdentifier` (add `accessibilityHint` when the action is non-obvious).

## Common Commands
Prefer XcodeBuildMCP tools when available; otherwise use the CLI fallback.

Build & run (simulator):
```bash
# Fast package-only compile
cd KirolePackage && swift build

# Full app build on simulator
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Tests:
```bash
# Full package test suite (Swift Testing)
cd KirolePackage && swift test

# Single test
cd KirolePackage && swift test --filter "MyTestSuite/testMethod"

# Simulator test run (only-testing filter)
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:KiroleFeatureTests/MyTestSuite/testMethod
```

Real device install (after simulator verification):
```bash
xcrun devicectl device install app --device <DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphoneos/Kirole.app
```

## Where to Look Next
- `AGENTS.md` — full rules, BLE protocol, Inku companion paradigm, onboarding detail.
- `SPEC.md` — product specification.
- `.cursor/rules/*.mdc` — Swift / SwiftUI / Testing / Concurrency / XcodeBuildMCP guidance.
- `TESTFLIGHT_GUIDE.md`, `TESTFLIGHT_PROGRESS.md` — release workflow state.

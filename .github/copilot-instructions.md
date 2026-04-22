# Copilot Custom Instructions

- This repository uses Swift 6.1+ and SwiftUI for iOS 17+ apps. All code should follow modern Swift and SwiftUI best practices.
- This is an iOS project NOT a pure Swift Package or macOS project. It utilises a local Swift Package (`KirolePackage`) wrapped in an Xcode workspace (`Kirole.xcworkspace`). This makes it easier for agents to work on the project.
- Use the Model-View (MV) pattern with native SwiftUI state management (`@State`, `@Observable`, `@Environment`, `@Binding`). Do not use ViewModels or MVVM.
- All concurrency must use Swift Concurrency (async/await, actors, @MainActor). Do not use GCD or completion handlers.
- Write all new code and features inside the Swift Package (`KirolePackage`), not in the app shell.
- Use the Swift Testing framework (`@Test`, `#expect`, `#require`) for all tests. Place tests in the package's `Tests/` directory.
- For test execution, either path is acceptable: `cd KirolePackage && swift test` (fast package-only) or the XcodeBuildMCP `test_sim_name_ws` tool (full simulator host). Pick based on whether the test exercises app-shell/UI lifecycle.
- Use XcodeBuildMCP tools for building and automation. Prefer these over raw xcodebuild when available.
- For data persistence, prefer SwiftData, Supabase (for synced data), or raw persistence (UserDefaults / JSON). Never use CoreData or CloudKit. For simple cases, prefer UserDefaults over SwiftData.
- Always provide `accessibilityLabel` and `accessibilityIdentifier` for interactive UI elements.
- Never log sensitive information or use insecure network calls. Secrets come from `Config/Secrets.xcconfig`, never from `Info.plist`.
- Canonical project rules, architecture, and workflow details: see `AGENTS.md` and `CLAUDE.md` at the repo root. Additional Swift/SwiftUI guidance lives in [`.cursor/rules/`](../.cursor/rules/).

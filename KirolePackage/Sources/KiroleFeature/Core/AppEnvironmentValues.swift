import SwiftUI

// MARK: - App Environment Keys
//
// Custom EnvironmentKey definitions for all app-wide @Observable singletons.
// Using MainActor.assumeIsolated in defaultValue getter — safe because SwiftUI
// always evaluates environment values during rendering, which runs on the main actor.
//
// Read in views:  @Environment(AppState.self) private var appState  (Observable style)
// Inject in tests: MyView().environment(\.appState, mockAppState)  (override style)
// Inject in app:  .environment(\.appState, AppState.shared)
//
// This is in addition to the existing @Observable injection used in injectAppEnvironment().
// Both approaches work: the @Entry-style keys unlock test overrides; the @Observable
// style is kept in views for type-safe access via @Environment(AppState.self).

private enum AppStateKey: EnvironmentKey {
    static var defaultValue: AppState {
        MainActor.assumeIsolated { AppState.shared }
    }
}

private enum ThemeManagerKey: EnvironmentKey {
    static var defaultValue: ThemeManager {
        MainActor.assumeIsolated { ThemeManager.shared }
    }
}

private enum AuthManagerKey: EnvironmentKey {
    static var defaultValue: AuthManager {
        MainActor.assumeIsolated { AuthManager.shared }
    }
}

private enum FocusServiceKey: EnvironmentKey {
    static var defaultValue: FocusSessionService {
        MainActor.assumeIsolated { FocusSessionService.shared }
    }
}

extension EnvironmentValues {
    public var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }

    public var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }

    public var authManager: AuthManager {
        get { self[AuthManagerKey.self] }
        set { self[AuthManagerKey.self] = newValue }
    }

    public var focusService: FocusSessionService {
        get { self[FocusServiceKey.self] }
        set { self[FocusServiceKey.self] = newValue }
    }
}

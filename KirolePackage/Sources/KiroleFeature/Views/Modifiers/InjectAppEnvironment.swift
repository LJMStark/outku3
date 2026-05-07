import SwiftUI

extension View {
    /// Re-inject all app-wide @Observable singletons into a new environment scope.
    ///
    /// SwiftUI .sheet / .fullScreenCover / .popover create a new environment
    /// scope that does NOT inherit values from the parent. Every root view
    /// inside such a closure must call this modifier.
    ///
    /// We inject via BOTH paths so all reading styles work:
    /// - @Environment(AppState.self)    — Observable-style read (most views)
    /// - @Environment(\.appState)       — Key-style read (new code, test overrides)
    ///
    /// Tests override the key-style path:  MyView().environment(\.appState, mockState)
    public func injectAppEnvironment() -> some View {
        self
            // Observable-style injection (for @Environment(Type.self) reads)
            .environment(AppState.shared)
            .environment(ThemeManager.shared)
            .environment(AuthManager.shared)
            .environment(FocusSessionService.shared)
            // Key-style injection (for @Environment(\.key) reads and test overrides)
            .environment(\.appState, AppState.shared)
            .environment(\.themeManager, ThemeManager.shared)
            .environment(\.authManager, AuthManager.shared)
            .environment(\.focusService, FocusSessionService.shared)
    }
}

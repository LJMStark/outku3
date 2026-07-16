import SwiftUI

private struct AppEnvironmentInjector: ViewModifier {
    @Environment(\.appState) private var appState
    @Environment(\.themeManager) private var themeManager
    @Environment(\.authManager) private var authManager
    @Environment(\.focusService) private var focusService

    func body(content: Content) -> some View {
        content
            // Observable-style injection (for @Environment(Type.self) reads)
            .environment(appState)
            .environment(themeManager)
            .environment(authManager)
            .environment(focusService)
            // Keep the key path intact for descendants that use key-style reads.
            .environment(\.appState, appState)
            .environment(\.themeManager, themeManager)
            .environment(\.authManager, authManager)
            .environment(\.focusService, focusService)
    }
}

extension View {
    /// Re-inject all app-wide @Observable dependencies into a new environment scope.
    ///
    /// Presented roots call this modifier so key-style and Observable-style readers receive the
    /// same instances, including previews and tests that override the key-style dependencies.
    ///
    /// We inject via BOTH paths so all reading styles work:
    /// - @Environment(AppState.self)    — Observable-style read (most views)
    /// - @Environment(\.appState)       — Key-style read (new code, test overrides)
    ///
    /// Values come from the parent key-style environment, whose defaults are the production
    /// singletons. This preserves a test or preview override instead of replacing it with `.shared`.
    public func injectAppEnvironment() -> some View {
        modifier(AppEnvironmentInjector())
    }
}

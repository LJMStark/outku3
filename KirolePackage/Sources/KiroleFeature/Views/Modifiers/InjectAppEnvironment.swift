import SwiftUI

extension View {
    /// Re-inject all three app-wide @Observable singletons.
    ///
    /// SwiftUI .sheet / .fullScreenCover / .popover create a new environment
    /// scope that does NOT inherit @Observable values from the parent. Every
    /// root view inside such a closure must call this modifier or access to
    /// AppState / ThemeManager / AuthManager will silently return nil and crash.
    public func injectAppEnvironment() -> some View {
        self
            .environment(AppState.shared)
            .environment(ThemeManager.shared)
            .environment(AuthManager.shared)
    }
}

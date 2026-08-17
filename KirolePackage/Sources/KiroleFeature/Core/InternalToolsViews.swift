import SwiftUI

/// Slots for app-target internal tools. Default is empty so App Store / package
/// builds render nothing. The InternalRelease app shell fills these under
/// `#if KIROLE_INTERNAL` and injects them at `ContentView`.
public struct InternalToolsViews {
    public var settingsSection: AnyView?
    public var focusDebugControls: AnyView?

    public init(settingsSection: AnyView? = nil, focusDebugControls: AnyView? = nil) {
        self.settingsSection = settingsSection
        self.focusDebugControls = focusDebugControls
    }

    public static var empty: InternalToolsViews { InternalToolsViews() }
}

private enum InternalToolsViewsKey: EnvironmentKey {
    // SwiftUI reads environment values on the main actor; AnyView is not Sendable.
    nonisolated(unsafe) static var defaultValue = InternalToolsViews()
}

extension EnvironmentValues {
    public var internalToolsViews: InternalToolsViews {
        get { self[InternalToolsViewsKey.self] }
        set { self[InternalToolsViewsKey.self] = newValue }
    }
}

extension View {
    public func internalToolsViews(_ views: InternalToolsViews) -> some View {
        environment(\.internalToolsViews, views)
    }
}

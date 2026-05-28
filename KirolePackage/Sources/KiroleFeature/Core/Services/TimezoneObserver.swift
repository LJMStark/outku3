import Foundation

// MARK: - Timezone Observer

/// Monitors NSSystemTimeZoneDidChange and fires a MainActor callback when the device
/// timezone changes at runtime. Used to surface a banner prompting the user to re-sync.
@MainActor
public final class TimezoneObserver {
    public static let shared = TimezoneObserver()

    private var observerToken: NSObjectProtocol?

    private init() {}

    public func startObserving(onChange: @escaping @MainActor (TimeZone) -> Void) {
        guard observerToken == nil else { return }
        observerToken = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onChange(TimeZone.current)
            }
        }
    }

    public func stopObserving() {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
        observerToken = nil
    }

}

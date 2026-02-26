import Foundation

public enum FocusMetricEvent: String, CaseIterable, Sendable {
    case authorizationRequested
    case authorizationApproved
    case authorizationDenied
    case protectionApplied
    case protectionApplyFailed
    case sessionFallback
    case sessionInterrupted
}

public actor FocusMetricsService {
    public static let shared = FocusMetricsService()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "focus.metrics."

    private init() {}

    public func record(_ event: FocusMetricEvent) {
        let key = keyPrefix + event.rawValue
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }

    public func count(for event: FocusMetricEvent) -> Int {
        defaults.integer(forKey: keyPrefix + event.rawValue)
    }
}

import EventKit
import Foundation

/// System access is independent from the user's persisted sync switch.
enum AppleIntegrationPermission: Sendable, Equatable {
    case notDetermined, fullAccess, denied, restricted, writeOnly, unavailable

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .fullAccess: self = .fullAccess
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .writeOnly: self = .writeOnly
        @unknown default: self = .unavailable
        }
    }

    var needsSettings: Bool {
        self != .notDetermined && self != .fullAccess
    }

    func message(for type: IntegrationType) -> String? {
        switch self {
        case .fullAccess: nil
        case .notDetermined:
            "Allow full access to connect \(type.rawValue)."
        case .denied:
            "\(type.rawValue) access is off. Allow Full Access in Settings to sync."
        case .restricted:
            "\(type.rawValue) access is restricted by Screen Time or device management. Check these restrictions in Settings."
        case .writeOnly:
            "Add Events Only does not let Kirole read your calendar. Choose Full Access in Settings."
        case .unavailable:
            "\(type.rawValue) access is unavailable. Check permissions in Settings."
        }
    }

    static func current(for type: IntegrationType) -> Self {
        Self(EKEventStore.authorizationStatus(for: type == .appleCalendar ? .event : .reminder))
    }
}

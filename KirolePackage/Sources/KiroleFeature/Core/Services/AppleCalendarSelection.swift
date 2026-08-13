import EventKit
import Foundation

public enum AppleCalendarSourceKind: String, Codable, Sendable, CaseIterable {
    case local
    case calDAV
    case exchange
    case subscription
    case birthday
    case other

    public init(calendarType: EKCalendarType) {
        switch calendarType {
        case .local:
            self = .local
        case .calDAV:
            self = .calDAV
        case .exchange:
            self = .exchange
        case .subscription:
            self = .subscription
        case .birthday:
            self = .birthday
        @unknown default:
            self = .other
        }
    }

    public var displayName: String {
        switch self {
        case .local: return "On My iPhone"
        case .calDAV: return "CalDAV / iCloud"
        case .exchange: return "Exchange"
        case .subscription: return "Subscribed Calendar"
        case .birthday: return "Birthdays"
        case .other: return "System Calendar"
        }
    }
}

/// A system calendar exposed through EventKit. `sourceKind` and `isSubscribed` are deliberately
/// separate because Apple reports some subscribed CalDAV calendars as `.calDAV` with
/// `isSubscribed == true`.
public struct AppleCalendarDescriptor: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let accountIdentifier: String
    public let accountTitle: String
    public let sourceKind: AppleCalendarSourceKind
    public let isSubscribed: Bool
    public let allowsContentModifications: Bool

    public init(
        id: String,
        title: String,
        accountIdentifier: String,
        accountTitle: String,
        sourceKind: AppleCalendarSourceKind,
        isSubscribed: Bool,
        allowsContentModifications: Bool
    ) {
        self.id = id
        self.title = title
        self.accountIdentifier = accountIdentifier
        self.accountTitle = accountTitle
        self.sourceKind = sourceKind
        self.isSubscribed = isSubscribed
        self.allowsContentModifications = allowsContentModifications
    }

    public var isReadOnly: Bool {
        isSubscribed || sourceKind == .subscription || !allowsContentModifications
    }

    public var isSelectable: Bool {
        sourceKind != .birthday
    }
}

/// Controls whether EventKit is being used as the native Apple Calendar integration or as a
/// credential-free bridge for CalDAV / Exchange / subscribed calendars. Mediated calendars are
/// deliberately read-only even when EventKit reports that the underlying account is writable.
public enum AppleCalendarSelectionMode: String, Codable, Sendable, Equatable {
    case nativeAppleCalendar
    case mediatedReadOnly
}

/// Describes why the calendar picker is being presented. Editing an existing connection only
/// changes its explicit calendar set. A mediated first connection is transactional: provider
/// state is not committed until the user taps Save.
public enum AppleCalendarSelectionIntent: String, Sendable, Equatable, Identifiable {
    case editExisting
    case connectMediated

    public var id: String { rawValue }

    var selectionModeForLoading: AppleCalendarSelectionMode? {
        switch self {
        case .editExisting:
            return nil
        case .connectMediated:
            return .mediatedReadOnly
        }
    }
}

@MainActor
public struct AppleCalendarSelectionActions {
    let saveIdentifiers: (Set<String>) async throws -> Void
    let saveMode: (AppleCalendarSelectionMode) async throws -> Void
    let connectAppleCalendar: () async throws -> Void
    let syncAppleCalendar: () async throws -> Void

    public init(
        saveIdentifiers: @escaping (Set<String>) async throws -> Void,
        saveMode: @escaping (AppleCalendarSelectionMode) async throws -> Void,
        connectAppleCalendar: @escaping () async throws -> Void,
        syncAppleCalendar: @escaping () async throws -> Void
    ) {
        self.saveIdentifiers = saveIdentifiers
        self.saveMode = saveMode
        self.connectAppleCalendar = connectAppleCalendar
        self.syncAppleCalendar = syncAppleCalendar
    }
}

/// Keeps the picker transaction independently testable without introducing a SwiftUI ViewModel.
@MainActor
public struct AppleCalendarSelectionCoordinator {
    private let intent: AppleCalendarSelectionIntent
    private let actions: AppleCalendarSelectionActions

    public init(
        intent: AppleCalendarSelectionIntent,
        actions: AppleCalendarSelectionActions
    ) {
        self.intent = intent
        self.actions = actions
    }

    public func cancel() {
        // Intentionally empty. Dismissing an uncommitted picker must not alter provider state.
    }

    public func save(selectedIdentifiers: Set<String>) async throws {
        try await actions.saveIdentifiers(selectedIdentifiers)

        if intent == .connectMediated {
            try await actions.saveMode(.mediatedReadOnly)
            try await actions.connectAppleCalendar()
        }

        try await actions.syncAppleCalendar()
    }
}

public protocol AppleCalendarSelectionPersisting: Sendable {
    func loadSelectedCalendarIdentifiers() async -> Set<String>?
    func saveSelectedCalendarIdentifiers(_ identifiers: Set<String>) async
    func loadSelectionMode() async -> AppleCalendarSelectionMode
    func saveSelectionMode(_ mode: AppleCalendarSelectionMode) async
}

public actor AppleCalendarSelectionStore: AppleCalendarSelectionPersisting {
    public static let shared = AppleCalendarSelectionStore()

    private static let selectedIdentifiersKey = "apple.selectedEventCalendarIdentifiers"
    private static let selectionModeKey = "apple.eventCalendarSelectionMode"

    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func loadSelectedCalendarIdentifiers() async -> Set<String>? {
        guard let stored = defaults.array(forKey: Self.selectedIdentifiersKey) as? [String] else {
            return nil
        }
        return Set(stored)
    }

    public func saveSelectedCalendarIdentifiers(_ identifiers: Set<String>) async {
        defaults.set(identifiers.sorted(), forKey: Self.selectedIdentifiersKey)
    }

    public func loadSelectionMode() async -> AppleCalendarSelectionMode {
        guard let rawValue = defaults.string(forKey: Self.selectionModeKey),
              let mode = AppleCalendarSelectionMode(rawValue: rawValue) else {
            return .nativeAppleCalendar
        }
        return mode
    }

    public func saveSelectionMode(_ mode: AppleCalendarSelectionMode) async {
        defaults.set(mode.rawValue, forKey: Self.selectionModeKey)
    }

    public static func resolveSelection(
        storedIdentifiers: Set<String>?,
        availableCalendars: [AppleCalendarDescriptor],
        selectionMode: AppleCalendarSelectionMode = .nativeAppleCalendar
    ) -> Set<String> {
        let selectableIdentifiers = Set(
            availableCalendars.lazy.filter(\.isSelectable).map(\.id)
        )
        guard let storedIdentifiers else {
            switch selectionMode {
            case .nativeAppleCalendar:
                return selectableIdentifiers
            case .mediatedReadOnly:
                return []
            }
        }
        return storedIdentifiers.intersection(selectableIdentifiers)
    }
}

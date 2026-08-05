import Foundation

struct DailyContentCommittedSnapshot: Sendable, Equatable, Codable {
    let state: DailyContentCommittedState
    let package: DailyContentPackage
    let eventFingerprints: [String: String]
    let personaFingerprint: String
    let eventDialogueFingerprint: String
    let staticCopyFingerprint: String
    let sourceFingerprint: String
}

struct DailyContentPendingDelivery: Sendable, Equatable, Codable {
    let transaction: DailyContentTransaction
    let sourceFingerprint: String
    let eventSourceFingerprint: String
    let eventFingerprints: [String: String]
    let personaFingerprint: String
    let eventDialogueFingerprint: String
    let staticCopyFingerprint: String
    let capturedStabilityGeneration: UInt64?

    @MainActor
    func matchesCurrentSource(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let appState = AppState.shared
        return eventSourceFingerprint == DailyContentSource.sourceFingerprint(
            events: appState.events,
            at: now,
            calendar: calendar,
            userProfile: appState.userProfile,
            customCompanions: appState.customCompanions
        )
    }
}

struct DailyContentStabilityCheckpoint: Sendable, Codable {
    let state: DailyContentStabilityState
    let hardwareEventsBaseline: [CalendarEvent]?
    let sourceFingerprint: String
}

struct DailyContentStabilityState: Sendable, Equatable, Codable {
    static let window: TimeInterval = 180

    private(set) var changedEventIDs: Set<String> = []
    private(set) var deadline: Date?
    private(set) var generation: UInt64 = 0

    mutating func recordChanges(
        from oldEvents: [CalendarEvent],
        to newEvents: [CalendarEvent],
        at now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let oldToday = Self.fingerprints(oldEvents, at: now, calendar: calendar)
        let newToday = Self.fingerprints(newEvents, at: now, calendar: calendar)
        let changed = Set(oldToday.keys).union(newToday.keys).filter {
            oldToday[$0] != newToday[$0]
        }
        guard !changed.isEmpty else { return false }
        bumpGeneration()
        changedEventIDs.formUnion(changed)
        deadline = now.addingTimeInterval(Self.window)
        return true
    }

    func readyGeneration(at now: Date) -> UInt64? {
        guard !changedEventIDs.isEmpty, let deadline, deadline <= now else { return nil }
        return generation
    }

    mutating func markCommitted(capturedGeneration: UInt64) {
        guard generation == capturedGeneration else { return }
        changedEventIDs.removeAll()
        deadline = nil
    }

    private mutating func bumpGeneration() {
        generation = generation == .max ? .max : generation + 1
    }

    private static func fingerprints(
        _ events: [CalendarEvent],
        at now: Date,
        calendar: Calendar
    ) -> [String: EventFingerprint] {
        var result: [String: EventFingerprint] = [:]
        for event in DailyContentSource.todayEvents(from: events, at: now, calendar: calendar)
            where result[event.id] == nil {
            result[event.id] = EventFingerprint(event)
        }
        return result
    }
}

private struct EventFingerprint: Equatable {
    let title: String
    let startTime: Date
    let endTime: Date
    let description: String?
    let location: String?
    let isAllDay: Bool

    init(_ event: CalendarEvent) {
        title = event.title
        startTime = event.startTime
        endTime = event.endTime
        description = event.description
        location = event.location
        isAllDay = event.isAllDay
    }
}

import Foundation

/// Identifies why a BLE sync was requested so the DayPack sender can distinguish routine refreshes
/// from changes that must replace the current hardware presentation.
public enum BLESyncTrigger: Sendable, Equatable {
    case automatic
    case requestRefresh
    case deviceWake
    case background
    case identityChange
    case manual

    fileprivate var defersPresentationOnlyDayPack: Bool {
        switch self {
        case .automatic, .requestRefresh, .deviceWake, .background:
            true
        case .identityChange, .manual:
            false
        }
    }

    var bypassesRoutineSyncInterval: Bool {
        switch self {
        case .identityChange, .manual:
            true
        case .automatic, .requestRefresh, .deviceWake, .background:
            false
        }
    }

    func merged(with newer: BLESyncTrigger) -> BLESyncTrigger {
        newer.mergePriority > mergePriority ? newer : self
    }

    /// Complete/Skip cancels the ordinary debounced DayPack so it cannot race the final
    /// TaskIn→Overview transaction. Identity and manual triggers still need a later full round
    /// (including PetStatus 0x01) because that transaction only sends DayPack + 0x1B.
    var survivesTaskActionPresentation: Bool {
        switch self {
        case .identityChange, .manual:
            true
        case .automatic, .requestRefresh, .deviceWake, .background:
            false
        }
    }

    private var mergePriority: Int {
        switch self {
        case .automatic, .requestRefresh, .deviceWake, .background:
            0
        case .identityChange:
            1
        case .manual:
            2
        }
    }
}

/// Keeps a device-owned schedule transition from being followed by a second App-owned full refresh.
/// The device already has the schedule and local time; only semantic data changes need another
/// DayPack while a timed event is on screen.
enum DayPackRefreshArbiter {
    static func hasActiveTimedEvent(in events: [CalendarEvent], at now: Date) -> Bool {
        events.contains { event in
            !event.isAllDay && event.startTime <= now && now < event.endTime
        }
    }

    static func shouldSend(
        trigger: BLESyncTrigger,
        wireContentChanged: Bool,
        hasActiveTimedEvent: Bool,
        hasPreviousSemanticFingerprint: Bool,
        semanticContentChanged: Bool
    ) -> Bool {
        guard wireContentChanged else { return false }
        guard trigger.defersPresentationOnlyDayPack,
              hasActiveTimedEvent,
              hasPreviousSemanticFingerprint,
              !semanticContentChanged else {
            return true
        }
        return false
    }
}

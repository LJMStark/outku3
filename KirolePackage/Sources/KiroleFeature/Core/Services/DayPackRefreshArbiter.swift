import Foundation

/// Identifies why a BLE sync was requested so the DayPack sender can distinguish a physical or
/// background refresh from an explicit user-requested refresh.
public enum BLESyncTrigger: Sendable, Equatable {
    case automatic
    case requestRefresh
    case deviceWake
    case background
    case manual

    fileprivate var defersPresentationOnlyDayPack: Bool {
        self != .manual
    }

    func merged(with newer: BLESyncTrigger) -> BLESyncTrigger {
        newer == .manual ? .manual : self
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

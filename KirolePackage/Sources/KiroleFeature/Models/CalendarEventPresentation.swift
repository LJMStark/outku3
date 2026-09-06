import Foundation

/// A read-only projection. Keep every original record for source-specific sync and editing,
/// so removing a direct Google connection immediately reveals its retained EventKit copy.
enum CalendarEventPresentation {
    static func events(
        from events: [CalendarEvent],
        googleCalendarWriteAccess: Bool
    ) -> [CalendarEvent] {
        let googleOccurrences = Set(events.lazy.filter { $0.source == .google }.compactMap(Occurrence.init))
        guard !googleOccurrences.isEmpty else { return events }
        // Prefer a writable Apple copy over a read-only Google connection. Keep the original
        // record and its source so edits still route through that provider's existing dispatcher.
        let preferredAppleOccurrences: Set<Occurrence> = googleCalendarWriteAccess ? [] : Set(
            events.lazy.filter {
                $0.source == .apple && $0.editCapabilities(googleCalendarWriteAccess: false).isEditable
            }.compactMap(Occurrence.init)
        )
        return events.filter { event in
            guard let occurrence = Occurrence(event) else { return true }
            switch event.source {
            case .apple:
                return !googleOccurrences.contains(occurrence) || preferredAppleOccurrences.contains(occurrence)
            case .google:
                return !preferredAppleOccurrences.contains(occurrence)
            case .outlook, .microsoftToDo:
                return true
            }
        }
    }

    private struct Occurrence: Hashable {
        let uid: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let title: String
        let description: String?
        let location: String?
        let participantNames: [String]
        let videoMeetingURL: URL?

        init?(_ event: CalendarEvent) {
            guard let uid = event.iCalendarUID,
                  !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            // UID is opaque: do not strip domains, case-fold, or substitute a title/time guess.
            self.uid = uid
            start = event.startTime
            end = event.endTime
            isAllDay = event.isAllDay
            // A failed Google fetch retains its cache. Keep both versions visible if EventKit
            // has different content, rather than hiding a local edit behind that stale cache.
            title = event.title
            description = event.description
            location = event.location
            participantNames = event.participants.map(\.name)
            videoMeetingURL = event.videoMeetingURL
        }
    }
}

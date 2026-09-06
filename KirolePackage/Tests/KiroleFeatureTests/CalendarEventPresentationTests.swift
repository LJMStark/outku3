import Foundation
import Testing
@testable import KiroleFeature

@Suite("Calendar source coexistence presentation")
struct CalendarEventPresentationTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A read-only Google connection does not hide a writable Apple event")
    func readOnlyGoogleKeepsEditableApple() {
        let events = [event("apple", source: .apple, appleWritable: true), event("google", source: .google)]
        let selected = CalendarEventPresentation.events(from: events, googleCalendarWriteAccess: false)
        #expect(selected.map(\.id) == ["apple"])
        #expect(selected.first?.editCapabilities(googleCalendarWriteAccess: false).isEditable == true)
        #expect(selected.first?.source == .apple)
        #expect(selected.first?.externalReference == events.first?.externalReference)
        #expect(events.count == 2)
    }

    @Test("Mirror selection preserves editing capability for every permission combination and arrival order")
    func editingCapabilityMatrix() {
        for googleWritable in [false, true] {
            for appleWritable in [false, true] {
                let apple = event("apple", source: .apple, appleWritable: appleWritable)
                let google = event("google", source: .google)
                let expectedID = !googleWritable && appleWritable ? "apple" : "google"
                for input in [[apple, google], [google, apple]] {
                    let selected = CalendarEventPresentation.events(from: input, googleCalendarWriteAccess: googleWritable)
                    #expect(selected.map(\.id) == [expectedID])
                    #expect(selected.first?.editCapabilities(googleCalendarWriteAccess: googleWritable).isEditable
                        == (googleWritable || appleWritable))
                }
            }
        }
    }

    @Test("Scope changes recompute the representative without altering either original")
    func permissionChanges() {
        let input = [event("apple", source: .apple, appleWritable: true), event("google", source: .google)]
        for writable in [false, true, false] {
            let selected = CalendarEventPresentation.events(from: input, googleCalendarWriteAccess: writable)
            #expect(selected.map(\.id) == [writable ? "google" : "apple"])
            #expect(selected.first?.editCapabilities(googleCalendarWriteAccess: writable).isEditable == true)
        }
        #expect(input.map(\.id) == ["apple", "google"])
    }

    @Test("Only the matching Apple mirror is hidden, independently of arrival order")
    func mirrors() {
        let apple = event("apple", source: .apple)
        let google = event("google", source: .google)
        let separate = event("separate", source: .apple, uid: "other")
        for input in [[apple, google, separate], [google, apple, separate]] {
            #expect(CalendarEventPresentation.events(from: input, googleCalendarWriteAccess: true).map(\.id) == ["google", "separate"])
            #expect(input.count == 3)
        }
    }

    @Test("Missing or different UIDs never collapse identical titles and times")
    func unknownIdentity() {
        for uid in [nil, "", " ", "different", "SHARED@example.com"] as [String?] {
            let input = [event("google", source: .google), event("apple", source: .apple, uid: uid)]
            #expect(CalendarEventPresentation.events(from: input, googleCalendarWriteAccess: true).count == 2)
        }
    }

    @Test("Recurring occurrences, changed duration and all-day differences stay distinct")
    func distinctOccurrences() {
        let google = event("google", source: .google)
        var later = event("later", source: .apple)
        later.startTime.addTimeInterval(86_400)
        later.endTime.addTimeInterval(86_400)
        var longer = event("longer", source: .apple)
        longer.endTime.addTimeInterval(60)
        var allDay = event("all-day", source: .apple)
        allDay.isAllDay = true
        #expect(CalendarEventPresentation.events(from: [google, later, longer, allDay], googleCalendarWriteAccess: true).count == 4)
    }

    @Test("Copies within one provider and Outlook records remain untouched")
    func sourceBoundaries() {
        for source in [EventSource.apple, .google, .outlook] {
            let input = [event("first", source: source), event("second", source: source)]
            #expect(CalendarEventPresentation.events(from: input, googleCalendarWriteAccess: false).map(\.id) == ["first", "second"])
        }
        #expect(CalendarEventPresentation.events(from: [
            event("google", source: .google), event("outlook", source: .outlook)
        ], googleCalendarWriteAccess: false).count == 2)
    }

    @Test("An offline Google cache cannot hide changed Apple content")
    @MainActor
    func divergentContent() {
        let google = event("google", source: .google)
        let original = event("apple", source: .apple)
        var title = original
        title.title = "Updated on Apple"
        var notes = original
        notes.description = "New notes"
        var location = original
        location.location = "New room"
        var attendees = original
        attendees.participants = [Participant(name: "Guest")]
        var meeting = original
        meeting.videoMeetingURL = URL(string: "https://meet.google.com/abc-defg-hij")
        let state = AppState.makeForTesting()
        state.events = [google, original]
        let baseline = HardwareContentFingerprint.structural(from: state, now: start, screenSize: .fourInch)
        for changed in [title, notes, location, attendees, meeting] {
            state.events = [google, changed]
            #expect(state.presentationEvents.map(\.id) == ["google", "apple"])
            #expect(state.presentationEvents.last?.source == .apple)
            #expect(HardwareContentFingerprint.structural(from: state, now: start, screenSize: .fourInch) != baseline)
        }
    }

    @Test("Disconnecting Google restores the retained Apple copy without a network fetch")
    @MainActor
    func disconnectedMirrorRestores() {
        let state = AppState.makeForTesting()
        state.events = [event("apple", source: .apple), event("google", source: .google)]
        #expect(state.presentationEvents.map(\.id) == ["google"])
        #expect(state.events.count == 2)
        let cleaned = state.integrationCoordinator.cleanupDisconnectedData(
            for: .googleCalendar, events: state.events, tasks: []
        )
        state.events = cleaned.events
        #expect(state.presentationEvents.map(\.id) == ["apple"])
    }

    @Test("Google API UID survives mapping and local persistence; missing UID remains readable")
    func identityMapping() throws {
        let data = Data(#"{"id":"remote","iCalUID":"shared@example.com","start":{"dateTime":"2026-09-06T09:00:00Z"},"end":{"dateTime":"2026-09-06T10:00:00Z"}}"#.utf8)
        let remote = try JSONDecoder().decode(GoogleCalendarEvent.self, from: data)
        let mapped = try #require(CalendarEvent.from(googleEvent: remote, googleCalendarId: "calendar"))
        #expect(mapped.iCalendarUID == "shared@example.com")
        let encoded = try JSONEncoder().encode(mapped)
        #expect(try JSONDecoder().decode(CalendarEvent.self, from: encoded).iCalendarUID == mapped.iCalendarUID)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "iCalendarUID")
        let withoutUID = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(CalendarEvent.self, from: withoutUID).iCalendarUID == nil)
    }

    @Test("Mirrors do not consume Schedule slots or alter the projected hardware fingerprint")
    @MainActor
    func hardwareProjection() {
        let originals = (0..<8).map { index in
            event("google-\(index)", source: .google, uid: "uid-\(index)")
        }
        let mirrors = (0..<8).map { index in
            event("apple-\(index)", source: .apple, uid: "uid-\(index)")
        }
        let state = AppState.makeForTesting()
        state.events = originals
        let before = HardwareContentFingerprint.structural(from: state, now: start, screenSize: .fourInch)
        state.events = mirrors + originals
        let projected = state.presentationEvents
        #expect(projected.map(\.id) == originals.map(\.id))
        #expect(BLEDataEncoder.encodeSchedule(projected, now: start) == BLEDataEncoder.encodeSchedule(originals, now: start))
        #expect(HardwareContentFingerprint.structural(from: state, now: start, screenSize: .fourInch) == before)
    }

    @Test("The frozen projection feeds the existing Schedule and DayPack encoders")
    @MainActor
    func frozenDatasets() {
        let now = Date()
        var google = event("google", source: .google)
        google.startTime = Calendar.current.startOfDay(for: now).addingTimeInterval(3_600)
        google.endTime = google.startTime.addingTimeInterval(3_600)
        var apple = event("apple", source: .apple)
        apple.startTime = google.startTime
        apple.endTime = google.endTime
        let state = AppState.makeForTesting()
        state.events = [apple, google]
        let frozen = state.presentationEvents
        let dayPack = DayPack(
            date: now, petDialogue: "Ready.", events: frozen.map { EventSummary(from: $0) },
            topTasks: [], settlementData: SettlementData(
                tasksCompleted: 0, tasksTotal: 0, pointsEarned: 0, petMood: "Happy",
                summaryMessage: "", encouragementMessage: ""
            )
        )
        let snapshot = OfflineDatasetSnapshot(tasks: [], events: frozen, dayPack: dayPack, screenSize: .fourInch)
        #expect(snapshot.schedulePayload[0] == ScheduleV2Codec.subVersion)
        #expect(snapshot.schedulePayload[4] == 1)
        #expect(dayPack.events.count == 1)
        #expect(snapshot.schedulePayload == BLEDataEncoder.encodeSchedule([google]))
        #expect(snapshot.dayPackPayload == BLEDataEncoder.encodeDayPack(dayPack, screenSize: .fourInch))
        #expect(state.events.count == 2)
    }

    private func event(
        _ id: String, source: EventSource, uid: String? = "shared@example.com", appleWritable: Bool = false
    ) -> CalendarEvent {
        let reference: ProviderItemReference? = source == .apple ? ProviderItemReference(
            provider: .appleCalendar, accountID: "apple-account", containerID: "calendar", itemID: id,
            allowsContentModifications: appleWritable
        ) : nil
        return CalendarEvent(id: id, externalReference: reference, iCalendarUID: uid, title: "Same title", startTime: start,
                      endTime: start.addingTimeInterval(3_600), source: source)
    }
}

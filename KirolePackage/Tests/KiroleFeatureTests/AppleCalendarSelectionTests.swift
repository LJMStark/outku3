import EventKit
import Foundation
import Testing
@testable import KiroleFeature

@Suite("Apple Calendar selection", .serialized)
struct AppleCalendarSelectionTests {
    @Test("Source types expose account-backed calendar kinds")
    func sourceKinds() {
        #expect(AppleCalendarSourceKind(calendarType: .local) == .local)
        #expect(AppleCalendarSourceKind(calendarType: .calDAV) == .calDAV)
        #expect(AppleCalendarSourceKind(calendarType: .exchange) == .exchange)
        #expect(AppleCalendarSourceKind(calendarType: .subscription) == .subscription)
        #expect(AppleCalendarSourceKind(calendarType: .birthday) == .birthday)
    }

    @Test("Subscribed and non-modifiable calendars are read-only")
    func readOnlyCapability() {
        let subscribed = AppleCalendarDescriptor(
            id: "feed",
            title: "Team Feed",
            accountIdentifier: "source-1",
            accountTitle: "Subscribed Calendars",
            sourceKind: .subscription,
            isSubscribed: true,
            allowsContentModifications: false
        )
        let exchange = AppleCalendarDescriptor(
            id: "work",
            title: "Work",
            accountIdentifier: "source-2",
            accountTitle: "Exchange",
            sourceKind: .exchange,
            isSubscribed: false,
            allowsContentModifications: true
        )
        let subscribedCalDAV = AppleCalendarDescriptor(
            id: "caldav-feed",
            title: "Remote Feed",
            accountIdentifier: "source-3",
            accountTitle: "CalDAV",
            sourceKind: .calDAV,
            isSubscribed: true,
            allowsContentModifications: false
        )

        #expect(subscribed.isReadOnly)
        #expect(subscribedCalDAV.sourceKind == .calDAV)
        #expect(subscribedCalDAV.isReadOnly)
        #expect(!exchange.isReadOnly)
        #expect(!EventKitService.canModifyCalendar(subscribed))
        #expect(EventKitService.canModifyCalendar(exchange))
        #expect(!EventKitService.canModifyCalendar(
            exchange,
            selectionMode: .mediatedReadOnly
        ))
    }

    @Test("Native Apple Calendar defaults an unsaved selection to every non-birthday calendar")
    func nativeDefaultSelection() {
        let calendars = [
            descriptor(id: "local", kind: .local),
            descriptor(id: "caldav", kind: .calDAV),
            descriptor(id: "exchange", kind: .exchange),
            descriptor(id: "feed", kind: .subscription, subscribed: true, writable: false),
            descriptor(id: "birthdays", kind: .birthday, writable: false),
        ]

        let selected = AppleCalendarSelectionStore.resolveSelection(
            storedIdentifiers: nil,
            availableCalendars: calendars,
            selectionMode: .nativeAppleCalendar
        )

        #expect(selected == Set(["local", "caldav", "exchange", "feed"]))
    }

    @Test("Mediated calendar selection stays empty until the user saves a choice")
    func mediatedDefaultSelectionRequiresConfirmation() {
        let calendars = [
            descriptor(id: "local", kind: .local),
            descriptor(id: "caldav", kind: .calDAV),
            descriptor(id: "exchange", kind: .exchange),
            descriptor(id: "feed", kind: .subscription, subscribed: true, writable: false),
        ]

        let selected = AppleCalendarSelectionStore.resolveSelection(
            storedIdentifiers: nil,
            availableCalendars: calendars,
            selectionMode: .mediatedReadOnly
        )

        #expect(selected.isEmpty)
    }

    @Test("Canceling a mediated connection has no provider or sync side effects")
    @MainActor
    func cancelDoesNotCommitConnection() {
        let recorder = AppleCalendarSelectionActionRecorder()
        let coordinator = AppleCalendarSelectionCoordinator(
            intent: .connectMediated,
            actions: recorder.actions
        )

        coordinator.cancel()

        #expect(recorder.recordedActions.isEmpty)
    }

    @Test("Saving a mediated choice persists it before connecting and syncing")
    @MainActor
    func saveCommitsBeforeConnectingAndSyncing() async throws {
        let recorder = AppleCalendarSelectionActionRecorder()
        let coordinator = AppleCalendarSelectionCoordinator(
            intent: .connectMediated,
            actions: recorder.actions
        )

        try await coordinator.save(selectedIdentifiers: ["caldav"])

        #expect(recorder.recordedActions == [
            .saveIdentifiers(["caldav"]),
            .saveMode(.mediatedReadOnly),
            .connectAppleCalendar,
            .syncAppleCalendar,
        ])
    }

    @Test("Editing an existing Apple selection does not reset its mode or reconnect the provider")
    @MainActor
    func editingExistingSelectionPreservesConnectionMode() async throws {
        let recorder = AppleCalendarSelectionActionRecorder()
        let coordinator = AppleCalendarSelectionCoordinator(
            intent: .editExisting,
            actions: recorder.actions
        )

        try await coordinator.save(selectedIdentifiers: ["work"])

        #expect(recorder.recordedActions == [
            .saveIdentifiers(["work"]),
            .syncAppleCalendar,
        ])
    }

    @Test("A failed save does not connect, clear a conflicting provider, or sync")
    @MainActor
    func failedSaveHasNoConnectionSideEffects() async {
        let recorder = AppleCalendarSelectionActionRecorder(failSelectionSave: true)
        let coordinator = AppleCalendarSelectionCoordinator(
            intent: .connectMediated,
            actions: recorder.actions
        )

        do {
            try await coordinator.save(selectedIdentifiers: ["caldav"])
            Issue.record("Expected selection persistence to fail")
        } catch {}

        #expect(recorder.recordedActions == [.saveIdentifiers(["caldav"])])
    }

    @Test("An explicit empty selection stays empty")
    func explicitEmptySelection() async throws {
        let suiteName = "AppleCalendarSelectionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppleCalendarSelectionStore(suiteName: suiteName)

        let initialSelection = await store.loadSelectedCalendarIdentifiers()
        #expect(initialSelection == nil)
        #expect(await store.loadSelectionMode() == .nativeAppleCalendar)
        await store.saveSelectedCalendarIdentifiers([])
        let savedSelection = await store.loadSelectedCalendarIdentifiers()
        #expect(savedSelection == [])

        await store.saveSelectedCalendarIdentifiers(["work", "personal"])
        let updatedSelection = await store.loadSelectedCalendarIdentifiers()
        #expect(updatedSelection == Set(["work", "personal"]))

        await store.saveSelectionMode(.mediatedReadOnly)
        #expect(await store.loadSelectionMode() == .mediatedReadOnly)
    }

    @Test("Stored selection ignores calendars that are no longer available")
    func staleSelectionIsIgnored() {
        let calendars = [
            descriptor(id: "local", kind: .local),
            descriptor(id: "exchange", kind: .exchange),
        ]

        let selected = AppleCalendarSelectionStore.resolveSelection(
            storedIdentifiers: Set(["exchange", "removed"]),
            availableCalendars: calendars
        )

        #expect(selected == Set(["exchange"]))
    }

    @Test("Provider identity is deterministic and separates recurring occurrences")
    func stableProviderIdentity() throws {
        let firstStart = Date(timeIntervalSince1970: 1_723_420_800)
        let firstEnd = firstStart.addingTimeInterval(3_600)
        let secondStart = firstStart.addingTimeInterval(7 * 86_400)
        let secondEnd = secondStart.addingTimeInterval(3_600)

        let first = try #require(EventKitService.stableProviderIdentifier(
            externalIdentifier: "provider-event",
            eventIdentifier: "local-event-1",
            calendarItemIdentifier: "local-item",
            startDate: firstStart,
            endDate: firstEnd
        ))
        let firstAgain = try #require(EventKitService.stableProviderIdentifier(
            externalIdentifier: "provider-event",
            eventIdentifier: "local-event-replaced-after-sync",
            calendarItemIdentifier: "local-item-replaced-after-sync",
            startDate: firstStart,
            endDate: firstEnd
        ))
        let second = try #require(EventKitService.stableProviderIdentifier(
            externalIdentifier: "provider-event",
            eventIdentifier: "local-event-2",
            calendarItemIdentifier: "local-item",
            startDate: secondStart,
            endDate: secondEnd
        ))

        #expect(first == firstAgain)
        #expect(first != second)
        #expect(EventKitService.stableProviderIdentifier(
            externalIdentifier: nil,
            eventIdentifier: "",
            calendarItemIdentifier: "",
            startDate: firstStart,
            endDate: firstEnd
        ) == nil)
    }

    @Test("Reminder identity prefers the account external ID and never invents a read UUID")
    func stableReminderIdentity() {
        #expect(EventKitService.stableReminderIdentifier(
            externalIdentifier: "provider-reminder",
            calendarItemIdentifier: "local-reminder"
        ) == "external:provider-reminder")
        #expect(EventKitService.stableReminderIdentifier(
            externalIdentifier: nil,
            calendarItemIdentifier: "local-reminder"
        ) == "item:local-reminder")
        #expect(EventKitService.stableReminderIdentifier(
            externalIdentifier: nil,
            calendarItemIdentifier: ""
        ) == nil)
    }

    private func descriptor(
        id: String,
        kind: AppleCalendarSourceKind,
        subscribed: Bool = false,
        writable: Bool = true
    ) -> AppleCalendarDescriptor {
        AppleCalendarDescriptor(
            id: id,
            title: id,
            accountIdentifier: "account-\(id)",
            accountTitle: "Account",
            sourceKind: kind,
            isSubscribed: subscribed,
            allowsContentModifications: writable
        )
    }
}

@MainActor
private final class AppleCalendarSelectionActionRecorder {
    enum Action: Equatable {
        case saveIdentifiers(Set<String>)
        case saveMode(AppleCalendarSelectionMode)
        case connectAppleCalendar
        case syncAppleCalendar
    }

    enum SaveError: Error {
        case failed
    }

    private let failSelectionSave: Bool
    private(set) var recordedActions: [Action] = []

    init(failSelectionSave: Bool = false) {
        self.failSelectionSave = failSelectionSave
    }

    var actions: AppleCalendarSelectionActions {
        AppleCalendarSelectionActions(
            saveIdentifiers: { [self] identifiers in
                recordedActions.append(.saveIdentifiers(identifiers))
                if failSelectionSave { throw SaveError.failed }
            },
            saveMode: { [self] mode in
                recordedActions.append(.saveMode(mode))
            },
            connectAppleCalendar: { [self] in
                recordedActions.append(.connectAppleCalendar)
            },
            syncAppleCalendar: { [self] in
                recordedActions.append(.syncAppleCalendar)
            }
        )
    }
}

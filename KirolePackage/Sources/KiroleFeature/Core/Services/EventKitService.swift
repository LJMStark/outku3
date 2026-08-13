import EventKit
import Foundation

// MARK: - EventKit Service

public actor EventKitService {
    public static let shared = EventKitService()

    private let eventStore = EKEventStore()
    private let calendarSelectionStore: any AppleCalendarSelectionPersisting

    private init(
        calendarSelectionStore: any AppleCalendarSelectionPersisting = AppleCalendarSelectionStore.shared
    ) {
        self.calendarSelectionStore = calendarSelectionStore
    }

    // MARK: - Authorization

    public var calendarAuthorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    public var remindersAuthorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    public func requestCalendarAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    public func requestRemindersAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    // MARK: - Calendar Events

    public func fetchTodayEvents() async throws -> [CalendarEvent] {
        guard calendarAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await queryEvents(from: startOfDay, to: endOfDay)
    }

    public func fetchWeekEvents() async throws -> [CalendarEvent] {
        guard calendarAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!

        return try await queryEvents(from: startOfWeek, to: endOfWeek)
    }

    private func queryEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        let storedSelection = await calendarSelectionStore.loadSelectedCalendarIdentifiers()
        let selectionMode = await calendarSelectionStore.loadSelectionMode()
        let availableCalendars = eventStore.calendars(for: .event)
        let descriptors = availableCalendars.map(Self.makeCalendarDescriptor)
        let selectedIdentifiers = AppleCalendarSelectionStore.resolveSelection(
            storedIdentifiers: storedSelection,
            availableCalendars: descriptors,
            selectionMode: selectionMode
        )
        let calendars = availableCalendars.filter {
            selectedIdentifiers.contains($0.calendarIdentifier)
        }
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.compactMap { event in
            guard Self.shouldSyncEvent(
                title: event.title ?? "",
                calendarType: event.calendar.type,
                isSubscribed: event.calendar.isSubscribed,
                calendarTitle: event.calendar.title
            ) else {
                return nil
            }
            let eventIdentifier = event.eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let calendarItemIdentifier = event.calendarItemIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let externalIdentifier = event.calendarItemExternalIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let stableProviderIdentifier = Self.stableProviderIdentifier(
                externalIdentifier: externalIdentifier,
                eventIdentifier: eventIdentifier,
                calendarItemIdentifier: calendarItemIdentifier,
                startDate: event.startDate,
                endDate: event.endDate
            ) else {
                return nil
            }
            let externalReference = ProviderItemReference(
                provider: .appleCalendar,
                accountID: event.calendar.source.sourceIdentifier,
                containerID: event.calendar.calendarIdentifier,
                itemID: stableProviderIdentifier,
                allowsContentModifications: Self.canModifyCalendar(
                    Self.makeCalendarDescriptor(event.calendar),
                    selectionMode: selectionMode
                )
            )
            let videoURL = VideoMeetingURLDetector.detect(description: event.notes, location: event.location)
                ?? event.url.flatMap { VideoMeetingURLDetector.isVideoMeetingURL($0) ? $0 : nil }
            return CalendarEvent(
                id: externalReference.stableLocalID,
                appleEventId: eventIdentifier.isEmpty ? nil : eventIdentifier,
                appleCalendarId: event.calendar?.calendarIdentifier,
                externalReference: externalReference,
                title: event.title ?? "Untitled Event",
                startTime: event.startDate,
                endTime: event.endDate,
                source: .apple,
                participants: event.attendees?.compactMap { attendee in
                    guard let name = attendee.name else { return nil }
                    return Participant(name: name)
                } ?? [],
                description: event.notes,
                location: event.location,
                isAllDay: event.isAllDay,
                lastModified: event.lastModifiedDate ?? Date(),
                videoMeetingURL: videoURL
            )
        }
    }

    /// EventKit identifiers can be replaced after a full account sync. Prefer the provider's
    /// external identifier and add the occurrence window because recurring events may share it.
    /// Local EventKit identifiers remain deterministic fallbacks; never mint a UUID while reading.
    nonisolated static func stableProviderIdentifier(
        externalIdentifier: String?,
        eventIdentifier: String,
        calendarItemIdentifier: String,
        startDate: Date,
        endDate: Date
    ) -> String? {
        if let externalIdentifier, !externalIdentifier.isEmpty {
            let startMilliseconds = Int64(startDate.timeIntervalSince1970 * 1_000)
            let endMilliseconds = Int64(endDate.timeIntervalSince1970 * 1_000)
            return "external:\(externalIdentifier)|start:\(startMilliseconds)|end:\(endMilliseconds)"
        }
        if !eventIdentifier.isEmpty {
            return "event:\(eventIdentifier)"
        }
        if !calendarItemIdentifier.isEmpty {
            return "item:\(calendarItemIdentifier)"
        }
        return nil
    }

    /// Excludes Apple reference data while retaining useful subscribed calendars such as
    /// team schedules. A locally-created event is never rejected just because its title is CJK.
    nonisolated static func shouldSyncEvent(
        title: String,
        calendarType: EKCalendarType,
        isSubscribed: Bool,
        calendarTitle: String
    ) -> Bool {
        if calendarType == .birthday { return false }

        let isSubscription = isSubscribed || calendarType == .subscription
        guard isSubscription else { return true }

        let normalizedCalendarTitle = calendarTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let holidayCalendarTitles: Set<String> = [
            "holiday", "holidays", "china holidays", "chinese holidays", "holidays in china",
            "节假日", "中国节假日", "中国大陆节假日", "节日", "中国节日", "节气",
            "節假日", "中國節假日", "中國大陸節假日", "節日", "中國節日", "節氣",
            "休日", "祝日", "공휴일", "대한민국 공휴일", "휴일"
        ]
        if holidayCalendarTitles.contains(normalizedCalendarTitle) {
            return false
        }

        let solarTerms: Set<String> = [
            "立春", "雨水", "惊蛰", "驚蟄", "春分", "清明", "谷雨", "穀雨",
            "立夏", "小满", "小滿", "芒种", "芒種", "夏至", "小暑", "大暑",
            "立秋", "处暑", "處暑", "白露", "秋分", "寒露", "霜降", "立冬",
            "小雪", "大雪", "冬至", "小寒", "大寒"
        ]
        let normalizedEventTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !solarTerms.contains(normalizedEventTitle)
    }

    /// Fetch events for a custom date range (used by AppleSyncEngine)
    public func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        guard calendarAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }
        return try await queryEvents(from: startDate, to: endDate)
    }

    // MARK: - Update Event

    public func updateEvent(
        identifier: String,
        title: String?,
        startDate: Date?,
        endDate: Date?,
        location: String?,
        notes: String?
    ) async throws {
        guard calendarAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        guard let ekEvent = eventStore.event(withIdentifier: identifier) else {
            throw EventKitError.eventNotFound
        }
        let descriptor = Self.makeCalendarDescriptor(ekEvent.calendar)
        let selectionMode = await calendarSelectionStore.loadSelectionMode()
        guard Self.canModifyCalendar(descriptor, selectionMode: selectionMode) else {
            throw EventKitError.calendarReadOnly
        }

        if let title { ekEvent.title = title }
        if let startDate { ekEvent.startDate = startDate }
        if let endDate { ekEvent.endDate = endDate }
        ekEvent.location = location
        ekEvent.notes = notes

        try eventStore.save(ekEvent, span: .thisEvent)
    }

    // MARK: - Reminders

    public func fetchIncompleteReminders() async throws -> [TaskItem] {
        try await fetchReminders(from: nil, to: nil)
    }

    public func fetchTodayReminders() async throws -> [TaskItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return try await fetchReminders(from: startOfDay, to: endOfDay)
    }

    private func fetchReminders(from startDate: Date?, to endDate: Date?) async throws -> [TaskItem] {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: startDate,
            ending: endDate,
            calendars: calendars
        )

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            eventStore.fetchReminders(matching: predicate) { reminders in
                let tasks = (reminders ?? []).compactMap(Self.mapReminderToTask)

                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: tasks)
            }
        }
    }

    private nonisolated static func mapReminderToTask(_ reminder: EKReminder) -> TaskItem? {
        let reminderIdentifier = reminder.calendarItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalIdentifier = reminder.calendarItemExternalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let calendar = reminder.calendar,
              let providerIdentifier = stableReminderIdentifier(
                externalIdentifier: externalIdentifier,
                calendarItemIdentifier: reminderIdentifier
              ) else {
            return nil
        }
        let reference = ProviderItemReference(
            provider: .appleReminders,
            accountID: calendar.source.sourceIdentifier,
            containerID: calendar.calendarIdentifier,
            itemID: providerIdentifier,
            remoteStatus: reminder.isCompleted ? "completed" : "incomplete",
            allowsContentModifications: calendar.allowsContentModifications
                && !calendar.isSubscribed
                && calendar.type != .subscription
        )

        return TaskItem(
            id: reference.stableLocalID,
            appleReminderId: reminderIdentifier.isEmpty ? nil : reminderIdentifier,
            appleExternalId: externalIdentifier,
            appleListId: calendar.calendarIdentifier,
            externalReference: reference,
            title: reminder.title ?? "Untitled Reminder",
            isCompleted: reminder.isCompleted,
            dueDate: reminder.dueDateComponents?.date,
            source: .apple,
            priority: mapPriority(reminder.priority),
            lastModified: reminder.lastModifiedDate ?? Date(),
            remoteUpdatedAt: reminder.lastModifiedDate,
            notes: reminder.notes
        )
    }

    nonisolated static func stableReminderIdentifier(
        externalIdentifier: String?,
        calendarItemIdentifier: String
    ) -> String? {
        if let externalIdentifier, !externalIdentifier.isEmpty {
            return "external:\(externalIdentifier)"
        }
        if !calendarItemIdentifier.isEmpty {
            return "item:\(calendarItemIdentifier)"
        }
        return nil
    }

    // MARK: - Update Reminder

    public func updateReminderCompletion(identifier: String, isCompleted: Bool) async throws {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.reminderNotFound
        }
        guard let calendar = reminder.calendar,
              calendar.allowsContentModifications,
              !calendar.isSubscribed,
              calendar.type != .subscription else {
            throw EventKitError.calendarReadOnly
        }

        reminder.isCompleted = isCompleted
        reminder.completionDate = isCompleted ? Date() : nil

        try eventStore.save(reminder, commit: true)
    }

    // MARK: - Create Reminder

    public func createReminder(
        title: String,
        dueDate: Date?,
        priority: TaskPriority,
        notes: String?,
        listId: String?
    ) async throws -> CreatedAppleReminderIdentity {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.priority = toEKPriority(priority)

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        if let listId,
           let calendar = eventStore.calendars(for: .reminder).first(where: { $0.calendarIdentifier == listId }) {
            reminder.calendar = calendar
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }
        guard let calendar = reminder.calendar,
              calendar.allowsContentModifications,
              !calendar.isSubscribed,
              calendar.type != .subscription else {
            throw EventKitError.calendarReadOnly
        }

        try eventStore.save(reminder, commit: true)
        let identifier = reminder.calendarItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalIdentifier = reminder.calendarItemExternalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let providerIdentifier = Self.stableReminderIdentifier(
                externalIdentifier: externalIdentifier,
                calendarItemIdentifier: identifier
              ) else {
            throw EventKitError.saveFailed
        }
        let reference = ProviderItemReference(
            provider: .appleReminders,
            accountID: calendar.source.sourceIdentifier,
            containerID: calendar.calendarIdentifier,
            itemID: providerIdentifier,
            remoteStatus: "incomplete",
            allowsContentModifications: true
        )
        return CreatedAppleReminderIdentity(
            calendarItemIdentifier: identifier,
            externalIdentifier: externalIdentifier,
            listIdentifier: calendar.calendarIdentifier,
            reference: reference
        )
    }

    // MARK: - Update Reminder Fields

    public func updateReminder(
        identifier: String,
        title: String,
        dueDate: Date?,
        priority: TaskPriority,
        notes: String?,
        isCompleted: Bool
    ) async throws {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.reminderNotFound
        }
        guard let calendar = reminder.calendar,
              calendar.allowsContentModifications,
              !calendar.isSubscribed,
              calendar.type != .subscription else {
            throw EventKitError.calendarReadOnly
        }

        reminder.title = title
        reminder.notes = notes
        reminder.priority = toEKPriority(priority)
        reminder.isCompleted = isCompleted
        reminder.completionDate = isCompleted ? Date() : nil

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        } else {
            reminder.dueDateComponents = nil
        }

        try eventStore.save(reminder, commit: true)
    }

    // MARK: - Delete Reminder

    public func deleteReminder(identifier: String) async throws {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.reminderNotFound
        }
        guard let calendar = reminder.calendar,
              calendar.allowsContentModifications,
              !calendar.isSubscribed,
              calendar.type != .subscription else {
            throw EventKitError.calendarReadOnly
        }

        try eventStore.remove(reminder, commit: true)
    }

    // MARK: - Fetch Completed Reminders

    public func fetchCompletedReminders(from startDate: Date, to endDate: Date) async throws -> [TaskItem] {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: startDate,
            ending: endDate,
            calendars: calendars
        )

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            eventStore.fetchReminders(matching: predicate) { reminders in
                let tasks = (reminders ?? []).compactMap(Self.mapReminderToTask)

                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: tasks)
            }
        }
    }

    // MARK: - Available Lists

    public func getAvailableReminderLists() -> [(id: String, title: String)] {
        eventStore.calendars(for: .reminder).map { ($0.calendarIdentifier, $0.title) }
    }

    public func getAvailableCalendars() -> [(id: String, title: String)] {
        availableEventCalendars().map { ($0.id, $0.title) }
    }

    public func availableEventCalendars() -> [AppleCalendarDescriptor] {
        eventStore.calendars(for: .event).map(Self.makeCalendarDescriptor)
    }

    public func selectedEventCalendarIdentifiers(
        selectionMode overrideSelectionMode: AppleCalendarSelectionMode? = nil
    ) async -> Set<String> {
        let storedSelection = await calendarSelectionStore.loadSelectedCalendarIdentifiers()
        let selectionMode = if let overrideSelectionMode {
            overrideSelectionMode
        } else {
            await calendarSelectionStore.loadSelectionMode()
        }
        let calendars = availableEventCalendars()
        return AppleCalendarSelectionStore.resolveSelection(
            storedIdentifiers: storedSelection,
            availableCalendars: calendars,
            selectionMode: selectionMode
        )
    }

    public func setSelectedEventCalendarIdentifiers(_ identifiers: Set<String>) async {
        let availableIdentifiers = Set(availableEventCalendars().filter(\.isSelectable).map(\.id))
        await calendarSelectionStore.saveSelectedCalendarIdentifiers(
            identifiers.intersection(availableIdentifiers)
        )
    }

    public func eventCalendarSelectionMode() async -> AppleCalendarSelectionMode {
        await calendarSelectionStore.loadSelectionMode()
    }

    public func setEventCalendarSelectionMode(_ mode: AppleCalendarSelectionMode) async {
        await calendarSelectionStore.saveSelectionMode(mode)
    }

    // MARK: - Helpers

    private nonisolated static func mapPriority(_ ekPriority: Int) -> TaskPriority {
        switch ekPriority {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .medium
        }
    }

    private func toEKPriority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    nonisolated static func canModifyCalendar(
        _ calendar: AppleCalendarDescriptor,
        selectionMode: AppleCalendarSelectionMode = .nativeAppleCalendar
    ) -> Bool {
        selectionMode == .nativeAppleCalendar && !calendar.isReadOnly
    }

    private nonisolated static func makeCalendarDescriptor(
        _ calendar: EKCalendar
    ) -> AppleCalendarDescriptor {
        AppleCalendarDescriptor(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            accountIdentifier: calendar.source.sourceIdentifier,
            accountTitle: calendar.source.title,
            sourceKind: AppleCalendarSourceKind(calendarType: calendar.type),
            isSubscribed: calendar.isSubscribed,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }
}

public struct CreatedAppleReminderIdentity: Sendable, Equatable {
    public let calendarItemIdentifier: String
    public let externalIdentifier: String?
    public let listIdentifier: String
    public let reference: ProviderItemReference

    public init(
        calendarItemIdentifier: String,
        externalIdentifier: String?,
        listIdentifier: String,
        reference: ProviderItemReference
    ) {
        self.calendarItemIdentifier = calendarItemIdentifier
        self.externalIdentifier = externalIdentifier
        self.listIdentifier = listIdentifier
        self.reference = reference
    }
}

// MARK: - EventKit Error

public enum EventKitError: LocalizedError, Sendable {
    case notAuthorized
    case reminderNotFound
    case eventNotFound
    case calendarReadOnly
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar or Reminders access not authorized"
        case .reminderNotFound:
            return "Reminder not found"
        case .eventNotFound:
            return "Event not found"
        case .calendarReadOnly:
            return "This calendar is read-only"
        case .saveFailed:
            return "Failed to save changes"
        }
    }
}

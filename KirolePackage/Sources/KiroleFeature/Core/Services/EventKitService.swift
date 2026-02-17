import EventKit
import Foundation

// MARK: - EventKit Service

public actor EventKitService {
    public static let shared = EventKitService()

    private let eventStore = EKEventStore()

    private init() {}

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

        return try queryEvents(from: startOfDay, to: endOfDay)
    }

    public func fetchWeekEvents() async throws -> [CalendarEvent] {
        guard calendarAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!

        return try queryEvents(from: startOfWeek, to: endOfWeek)
    }

    private func queryEvents(from startDate: Date, to endDate: Date) throws -> [CalendarEvent] {
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                id: event.eventIdentifier,
                appleEventId: event.eventIdentifier,
                appleCalendarId: event.calendar.calendarIdentifier,
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
                lastModified: event.lastModifiedDate ?? Date()
            )
        }
    }

    /// Fetch events for a custom date range (used by AppleSyncEngine)
    public func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        guard calendarAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }
        return try queryEvents(from: startDate, to: endDate)
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
            eventStore.fetchReminders(matching: predicate) { reminders in
                let tasks = (reminders ?? []).map { self.mapReminderToTask($0) }
                continuation.resume(returning: tasks)
            }
        }
    }

    private func mapReminderToTask(_ reminder: EKReminder) -> TaskItem {
        TaskItem(
            id: reminder.calendarItemIdentifier,
            appleReminderId: reminder.calendarItemIdentifier,
            appleExternalId: reminder.calendarItemExternalIdentifier,
            appleListId: reminder.calendar.calendarIdentifier,
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

    // MARK: - Update Reminder

    public func updateReminderCompletion(identifier: String, isCompleted: Bool) async throws {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.reminderNotFound
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
    ) async throws -> (identifier: String, externalIdentifier: String) {
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

        try eventStore.save(reminder, commit: true)
        return (reminder.calendarItemIdentifier, reminder.calendarItemExternalIdentifier ?? "")
    }

    // MARK: - Update Reminder Fields

    public func updateReminder(
        identifier: String,
        title: String?,
        dueDate: Date?,
        priority: TaskPriority?,
        notes: String?,
        isCompleted: Bool?
    ) async throws {
        guard remindersAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.reminderNotFound
        }

        if let title { reminder.title = title }
        if let notes { reminder.notes = notes }
        if let priority { reminder.priority = toEKPriority(priority) }
        if let isCompleted {
            reminder.isCompleted = isCompleted
            reminder.completionDate = isCompleted ? Date() : nil
        }
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
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
            eventStore.fetchReminders(matching: predicate) { reminders in
                let tasks = (reminders ?? []).map { self.mapReminderToTask($0) }
                continuation.resume(returning: tasks)
            }
        }
    }

    // MARK: - Available Lists

    public func getAvailableReminderLists() -> [(id: String, title: String)] {
        eventStore.calendars(for: .reminder).map { ($0.calendarIdentifier, $0.title) }
    }

    public func getAvailableCalendars() -> [(id: String, title: String)] {
        eventStore.calendars(for: .event).map { ($0.calendarIdentifier, $0.title) }
    }

    // MARK: - Helpers

    private func mapPriority(_ ekPriority: Int) -> TaskPriority {
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
}

// MARK: - EventKit Error

public enum EventKitError: LocalizedError, Sendable {
    case notAuthorized
    case reminderNotFound
    case eventNotFound
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar or Reminders access not authorized"
        case .reminderNotFound:
            return "Reminder not found"
        case .eventNotFound:
            return "Event not found"
        case .saveFailed:
            return "Failed to save changes"
        }
    }
}

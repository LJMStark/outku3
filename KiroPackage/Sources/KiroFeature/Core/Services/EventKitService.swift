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

        return try fetchEvents(from: startOfDay, to: endOfDay)
    }

    public func fetchWeekEvents() async throws -> [CalendarEvent] {
        guard calendarAuthorizationStatus == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!

        return try fetchEvents(from: startOfWeek, to: endOfWeek)
    }

    private func fetchEvents(from startDate: Date, to endDate: Date) throws -> [CalendarEvent] {
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled Event",
                startTime: event.startDate,
                endTime: event.endDate,
                source: .apple,
                participants: event.attendees?.compactMap { attendee in
                    guard let name = attendee.name else { return nil }
                    return Participant(name: name)
                } ?? [],
                description: event.notes,
                location: event.location
            )
        }
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
            title: reminder.title ?? "Untitled Reminder",
            isCompleted: reminder.isCompleted,
            dueDate: reminder.dueDateComponents?.date,
            source: .apple,
            priority: mapPriority(reminder.priority)
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

    // MARK: - Helpers

    private func mapPriority(_ ekPriority: Int) -> TaskPriority {
        switch ekPriority {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .medium
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

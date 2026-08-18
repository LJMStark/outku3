import Foundation

/// Task-bar / schedule identity used to decide whether OfflineSync should COMMIT.
///
/// Phone-only copy (pet dialogue, day summary, settlement prose, live focus minutes)
/// is intentionally absent. Those fields still ride along inside DayPack when a
/// structural commit happens, but they must not start a hardware refresh by themselves.
enum HardwareContentFingerprint {
    static func companionKey(from profile: UserProfile) -> String {
        if let id = profile.customCompanionId {
            return "custom:\(id.uuidString)"
        }
        return "builtIn:\(profile.companionCharacter.rawValue)"
    }

    @MainActor
    static func structural(
        from appState: AppState,
        now: Date,
        screenSize: ScreenSize,
        calendar: Calendar = .current
    ) -> String {
        structural(
            tasks: appState.tasks,
            events: appState.events,
            now: now,
            screenSize: screenSize,
            deviceMode: appState.deviceMode,
            companionKey: companionKey(from: appState.userProfile),
            calendar: calendar
        )
    }

    static func structural(
        tasks: [TaskItem],
        events: [CalendarEvent],
        now: Date,
        screenSize: ScreenSize,
        deviceMode: DeviceMode,
        companionKey: String = "",
        calendar: Calendar = .current
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        let todayTasks = tasks
            .filter { $0.isInTodayDisplay(on: now, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.id != rhs.id { return lhs.id < rhs.id }
                return lhs.title < rhs.title
            }
        let todayEvents = events
            .filter { calendar.isDate( $0.startTime, inSameDayAs: now) }
            .sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
                return lhs.id < rhs.id
            }
        let topTasks = DayPackGenerator.topTaskSummaries(
            from: tasks,
            screenSize: screenSize,
            on: now,
            calendar: calendar
        )

        var parts: [String] = [
            "date=\(dateFormatter.string(from: now))",
            "deviceMode=\(deviceMode.rawValue)",
            "companion=\(companionKey)",
            "agenda=\(currentAgendaKey(events: todayEvents, topTasks: topTasks, now: now))",
            "events.count=\(todayEvents.count)",
        ]

        for event in todayEvents.prefix(8) {
            parts.append("event.id=\(event.id)")
            parts.append("event.title=\(event.title)")
            parts.append("event.start=\(Int(event.startTime.timeIntervalSince1970))")
            parts.append("event.end=\(Int(event.endTime.timeIntervalSince1970))")
            parts.append("event.allDay=\(event.isAllDay ? 1 : 0)")
            parts.append("event.desc=\(event.description ?? "")")
        }

        parts.append("todayTasks.count=\(todayTasks.count)")
        for task in todayTasks.prefix(10) {
            let due = task.dueDate.map { timeFormatter.string(from: $0) } ?? ""
            parts.append("task.id=\(task.id)")
            parts.append("task.title=\(task.title)")
            parts.append("task.completed=\(task.isCompleted ? 1 : 0)")
            parts.append("task.priority=\(task.priority.rawValue)")
            parts.append("task.due=\(due)")
            parts.append("task.pending=\(task.pendingDeletion ? 1 : 0)")
        }

        parts.append("topTasks.count=\(topTasks.count)")
        for task in topTasks {
            parts.append("top.id=\(task.id)")
            parts.append("top.title=\(task.title)")
            parts.append("top.completed=\(task.isCompleted ? 1 : 0)")
            parts.append("top.priority=\(task.priority)")
            parts.append("top.due=\(task.dueTime ?? "")")
        }

        return DayPack.framedFingerprint(parts)
    }

    /// Stable slot for "the schedule/task the device is currently pointing at".
    /// Crossing into the next event or next incomplete task is a structural change;
    /// ticking focus minutes is not.
    static func currentAgendaKey(
        events: [CalendarEvent],
        topTasks: [TaskSummary],
        now: Date
    ) -> String {
        if let current = events.first(where: { event in
            !event.isAllDay && event.startTime <= now && now < event.endTime
        }) {
            return "now-event:\(current.id)"
        }
        if let next = events.first(where: { $0.startTime > now }) {
            return "next-event:\(next.id)"
        }
        if let task = topTasks.first {
            return "next-task:\(task.id)"
        }
        return "idle"
    }
}

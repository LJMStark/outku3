import Foundation

// MARK: - Time of Day

public enum TimeOfDay: String, Sendable {
    case morning, afternoon, evening, night

    /// Determine time of day from a given date (defaults to now)
    public static func current(at date: Date = Date()) -> TimeOfDay {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

// MARK: - Day Pack Generator

/// 生成发送到 E-ink 设备的 Day Pack 数据
@MainActor
public final class DayPackGenerator {
    public static let shared = DayPackGenerator()
    private let textService = CompanionTextService.shared

    private init() {}

    public func generateDayPack(
        pet: Pet, tasks: [TaskItem], events: [CalendarEvent],
        weather: Weather, deviceMode: DeviceMode,
        userProfile: UserProfile = .default,
        screenSize: ScreenSize = .fourInch,
        petDialogue: String = ""
    ) async -> DayPack {
        let todayTasks = tasks.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false }
        let todayEvents = events
            .filter { Calendar.current.isDateInToday($0.startTime) }
            .sorted { $0.startTime < $1.startTime }

        // v2.5.0: one pet bubble, sourced from the App's currentPetDialogue (the same line the
        // App home shows). Fall back to a phase-appropriate companion line if not yet computed.
        let bubble = petDialogue.isEmpty
            ? await textService.generateCompanionPhrase(petMood: pet.mood, timeOfDay: TimeOfDay.current(), userProfile: userProfile)
            : petDialogue

        let eventSummaries = todayEvents.prefix(8).map { EventSummary(from: $0) }

        // box② "day at a glance" — events-only summary generated from today's event details.
        let daySummary = await textService.generateDaySummary(
            events: eventSummaries, petName: pet.name, userProfile: userProfile
        )

        let topTasks = todayTasks
            .filter { !$0.isCompleted }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
            .prefix(screenSize.maxTasks)
            .map { TaskSummary(from: $0) }

        // box③ "First up": next upcoming event, else the top (highest-priority) incomplete task.
        let firstUp = Self.firstUpLabel(events: todayEvents, fallbackTaskTitle: topTasks.first?.title)

        return DayPack(
            date: Date(),
            weather: WeatherInfo(from: weather),
            deviceMode: deviceMode,
            focusChallengeEnabled: false,
            petDialogue: bubble,
            daySummary: daySummary,
            firstUp: firstUp,
            events: Array(eventSummaries),
            topTasks: Array(topTasks),
            settlementData: await generateSettlementData(tasks: todayTasks, events: todayEvents, pet: pet, userProfile: userProfile)
        )
    }

    public func generateTaskInPage(task: TaskItem, pet: Pet, userProfile: UserProfile = .default) async -> TaskInPageData {
        let encouragement = await textService.generateTaskEncouragement(taskTitle: task.title, petName: pet.name, petMood: pet.mood, userProfile: userProfile)
        let overview = await taskOverview(for: task.notes)
        return TaskInPageData(
            taskId: task.id, taskTitle: task.title,
            taskDescription: overview,
            encouragement: encouragement
        )
    }

    /// In-task "Overview" (the task-content line). The AI generates it and self-judges whether it
    /// understands the note — summarizing when it does, returning the note verbatim when it does
    /// not (client decision). Returns nil when there is nothing to show; falls back to the verbatim
    /// (truncated) note only when AI is unavailable.
    func taskOverview(for rawNotes: String?) async -> String? {
        let notes = rawNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notes.isEmpty else { return nil }
        if let aiResult = await textService.generateTaskOverview(notes: notes) {
            return aiResult                                               // AI summary, or verbatim if it was unsure
        }
        return CompanionTextService.enforceByteBudget(notes, maxBytes: Self.taskDescriptionByteBudget)  // AI off → verbatim
    }

    // MARK: - Private Helpers

    /// box③ "First up" label: the next upcoming event ("HH:mm Title", or just the title for an
    /// all-day event), else the supplied top-task title, else "". Recomputed every sync relative
    /// to `now`, so an event drops to the fallback once it has started.
    nonisolated static func firstUpLabel(
        events: [CalendarEvent], fallbackTaskTitle: String?, now: Date = Date()
    ) -> String {
        if let next = events.filter({ $0.startTime > now }).min(by: { $0.startTime < $1.startTime }) {
            if next.isAllDay { return next.title }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: next.startTime)) \(next.title)"
        }
        return fallbackTaskTitle ?? ""
    }

    /// Wire budget for TaskInPage.TaskDescription (protocol §4.8). The verbatim note is truncated
    /// to this when AI is unavailable.
    static let taskDescriptionByteBudget = 100

    /// 结算完成数统计。客户 docx「页面四」：日程无法打卡，但只要客户未取消即视为完成一项任务，
    /// 计入完成数与积分。
    ///
    /// 计数口径：只统计**已结束**（`endTime <= now`）的日程。`generateDayPack` 会在每次 BLE
    /// 同步（白天每小时、硬件唤醒）时重算结算数据并下发硬件，并非只在日终跑；若把今天尚未发生的
    /// 日程也算成已完成，空任务日清晨就会误显示「Perfect day / 满分」。按 `endTime <= now` 过滤后：
    /// 日终结算时当天日程均已结束 → 全部计入（满足客户需求），日间则只计已发生的日程作为实时进度。
    ///
    /// 关于「取消」：Google 日历全量同步默认 `showDeleted=false`，已取消事件不会返回，下次全量
    /// 替换后即从今日列表消失。**被拒绝（declined）的邀请仍会返回并计入** —— 「declined 是否等同
    /// 已取消」是产品口径问题，已列入《待客户确认问题清单》，此处不擅自过滤。
    ///
    /// 已知取舍（跨午夜事件）：`endTime <= now` 让**全天事件**（endTime=次日 00:00）白天不会误计入
    /// 这一常见情形成立；代价是**跨天事件**（今天开始、明天结束）今天因 `endTime > now` 不计、次日又因
    /// `isDateInToday(startTime)` 不在今天而落空 → 永不计入。改用 `startTime <= now` 反而会让全天事件
    /// 从午夜就误计入（弊大于利），故保留此谓词；跨午夜事件的归属是产品口径问题，已列入待客户确认清单。
    nonisolated static func settlementCounts(
        tasks: [TaskItem], events: [CalendarEvent], now: Date = Date()
    ) -> (completed: Int, total: Int) {
        let completedTasks = tasks.filter { $0.isCompleted }.count
        let occurredEvents = events.filter { $0.endTime <= now }.count
        return (completed: completedTasks + occurredEvents,
                total: tasks.count + occurredEvents)
    }

    private func generateSettlementData(tasks: [TaskItem], events: [CalendarEvent], pet: Pet, userProfile: UserProfile = .default) async -> SettlementData {
        // 客户 docx 页面四：日程无法打卡，但只要未取消即视为完成一项任务，计入完成数/积分。
        let counts = Self.settlementCounts(tasks: tasks, events: events)
        let completed = counts.completed
        let total = counts.total
        let rate = total > 0 ? Double(completed) / Double(total) : 0
        let focusStats = FocusSessionService.shared.statistics
        let energyBottles = await LocalStorage.shared.loadEnergyBottles()

        let aiMessage = await textService.generateSettlementMessage(
            tasksCompleted: completed,
            tasksTotal: total,
            petName: pet.name,
            focusTimeToday: Int(focusStats.todayFocusTime / 60),
            energyBottles: energyBottles, // Loaded actual energy bottles score
            userProfile: userProfile
        )

        let (summary, encouragement): (String, String) = {
            switch rate {
            case 1.0...: return ("Perfect day! All tasks completed!", aiMessage)
            case 0.7..<1.0: return ("Great progress today!", aiMessage)
            case 0.3..<0.7: return ("Good effort today.", aiMessage)
            case 0.0..<0.3 where completed > 0: return ("You made a start today.", aiMessage)
            default: return ("Rest day?", aiMessage)
            }
        }()

        return SettlementData(
            tasksCompleted: completed, tasksTotal: total, pointsEarned: completed * 10,
            petMood: pet.mood.rawValue,
            summaryMessage: summary, encouragementMessage: encouragement,
            totalFocusMinutes: Int(focusStats.todayFocusTime / 60),
            focusSessionCount: focusStats.todaySessions,
            longestFocusMinutes: focusStats.longestSessionMinutes,
            interruptionCount: focusStats.interruptionCount,
            totalEnergyBottles: energyBottles
        )
    }

}

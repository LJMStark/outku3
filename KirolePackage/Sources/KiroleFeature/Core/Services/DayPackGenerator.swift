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

    /// box② DaySummary cache (date + event digest → text). Avoids regenerating the LLM summary on
    /// every BLE sync when today's events have not changed — which also kept the DayPack fingerprint
    /// churning (LLM text varies) and forced needless re-pushes.
    private var daySummaryCache: (key: String, text: String)?

    /// 页面四文案缓存（同 daySummaryCache 动机）：key 覆盖全部生成素材（日期、事件摘要含类别、
    /// 完成数、专注分钟、金句分支），素材不变则复用——不重打 LLM、不搅动指纹。
    private var settlementTextCache: (key: String, review: String, quote: String)?

    private init() {}

    public func generateDayPack(
        pet: Pet, tasks: [TaskItem], events: [CalendarEvent],
        weather: Weather, deviceMode: DeviceMode,
        userProfile: UserProfile = .default,
        screenSize: ScreenSize = .fourInch,
        petDialogue: String = ""
    ) async -> DayPack {
        let todayTasks = tasks.filter { $0.isInTodayDisplay() }
        let todayEvents = events
            .filter { Calendar.current.isDateInToday($0.startTime) }
            .sorted { $0.startTime < $1.startTime }

        // v2.5.0: one pet bubble, sourced from the App's currentPetDialogue (the same line the
        // App home shows). Fall back to a phase-appropriate companion line if not yet computed.
        let bubble = petDialogue.isEmpty
            ? await textService.generateCompanionPhrase(petMood: pet.mood, timeOfDay: TimeOfDay.current(), userProfile: userProfile)
            : petDialogue

        let uncategorizedEvents = todayEvents.prefix(8).map { EventSummary(from: $0) }
        // Category tagging and the neutral day summary depend on the same immutable event snapshot,
        // not on each other's result. Run both LLM-backed operations concurrently so a cold sync
        // waits for the slower request instead of adding both request durations together.
        async let categorizedEvents = EventCategoryService.shared.categorized(uncategorizedEvents)
        async let generatedDaySummary = cachedDaySummary(for: uncategorizedEvents)
        let (eventSummaries, daySummary) = await (categorizedEvents, generatedDaySummary)

        // 手动加入 Today 的任务先于自然到期任务；组内再按 priority、dueDate、id 定序。
        // Swift sort 不稳定，保留完整兜底顺序，确保截断到 maxTasks 后结果可复现。
        let topTasks = todayTasks
            .filter { !$0.isCompleted }
            .sorted {
                let lhsManual = $0.isManuallySelectedForToday()
                let rhsManual = $1.isManuallySelectedForToday()
                if lhsManual != rhsManual { return lhsManual }
                if $0.priority.rawValue != $1.priority.rawValue {
                    return $0.priority.rawValue > $1.priority.rawValue
                }
                let lhsDue = $0.dueDate ?? .distantFuture
                let rhsDue = $1.dueDate ?? .distantFuture
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                return $0.id < $1.id
            }
            .prefix(screenSize.maxTasks)
            .map { TaskSummary(from: $0) }

        // box③ "First up": next upcoming event, else the top (highest-priority) incomplete task.
        let firstUp = Self.firstUpLabel(events: todayEvents, fallbackTaskTitle: topTasks.first?.title)

        let settlementData = await generateSettlementData(tasks: todayTasks, events: todayEvents, pet: pet, userProfile: userProfile)
        // 页面四 每日总结（v2.5.30）：概况点评 + 分支金句；素材未变走缓存。
        let settlementTexts = await cachedSettlementTexts(
            events: Array(eventSummaries), todayEvents: todayEvents,
            settlement: settlementData, pet: pet, userProfile: userProfile
        )
        return DayPack(
            date: Date(),
            weather: WeatherInfo(from: weather),
            deviceMode: deviceMode,
            focusChallengeEnabled: false,
            petDialogue: bubble,
            daySummary: daySummary,
            firstUp: firstUp,
            settlementReview: settlementTexts.review,
            settlementQuote: settlementTexts.quote,
            events: Array(eventSummaries),
            topTasks: Array(topTasks),
            settlementData: settlementData
        )
    }

    /// Returns the box② DaySummary for `events`, reusing the cached text while today's event digest
    /// is unchanged — so an unchanged day does not re-hit the LLM or churn the DayPack fingerprint.
    private func cachedDaySummary(for events: [EventSummary]) async -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // key 含 endTime（v2.5.31）：digest 已喂结束时间给 AI，改期改时长同样要触发重新生成。
        let key = formatter.string(from: Date()) + "#"
            + events.map { "\($0.time)|\($0.endTime)|\($0.title)" }.joined(separator: "\u{1F}")
        if let cache = daySummaryCache, cache.key == key { return cache.text }
        let text = await textService.generateDaySummary(events: events)
        daySummaryCache = (key, text)
        return text
    }

    /// 页面四两段文案（概况点评 + 分支金句），素材键未变时复用缓存。
    /// key 含事件类别：异步分类晚到（缓存 miss → 下轮 AI 结果落地）时会重新生成——与
    /// Category 进指纹的既有约定同一逻辑，保证死线事件"必提"不被过期缓存吞掉。
    private func cachedSettlementTexts(
        events: [EventSummary], todayEvents: [CalendarEvent],
        settlement: SettlementData, pet: Pet, userProfile: UserProfile,
        now: Date = Date()
    ) async -> (review: String, quote: String) {
        let combinedMinutes = Self.scheduledEventMinutes(events: todayEvents) + settlement.totalFocusMinutes
        let unfinishedEvents = todayEvents.filter { $0.endTime > now }.count
        let branch = Self.settlementQuoteBranch(
            completed: settlement.tasksCompleted, total: settlement.tasksTotal,
            unfinishedEvents: unfinishedEvents, combinedMinutes: combinedMinutes
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // key 含当前 IP（内置 rawValue + 自定义 id）：金句是人格口吻，切换伙伴/自定义角色后
        // 必须重新生成，否则旧角色的口吻会一直缓存到其他素材变化为止。
        let key = formatter.string(from: Date()) + "#"
            + events.map { "\($0.time)|\($0.title)|\($0.category.rawValue)" }.joined(separator: "\u{1F}")
            + "#\(settlement.tasksCompleted)/\(settlement.tasksTotal)#\(settlement.totalFocusMinutes)#\(branch)"
            + "#\(userProfile.companionCharacter.rawValue)#\(userProfile.customCompanionId?.uuidString ?? "-")"
        if let cache = settlementTextCache, cache.key == key { return (cache.review, cache.quote) }

        // 两段文案互不依赖，并发生成（同 categorize/daySummary 的既有并发模式）。
        async let review = textService.generateSettlementReview(
            events: events, focusMinutes: settlement.totalFocusMinutes,
            tasksCompleted: settlement.tasksCompleted, tasksTotal: settlement.tasksTotal
        )
        async let quote = textService.generateSettlementQuote(
            branch: branch, petName: pet.name, petMood: pet.mood,
            tasksCompleted: settlement.tasksCompleted, tasksTotal: settlement.tasksTotal,
            focusMinutes: settlement.totalFocusMinutes, userProfile: userProfile
        )
        let result = (review: await review, quote: await quote)
        settlementTextCache = (key, result.review, result.quote)
        return result
    }

    public func generateTaskInPage(task: TaskItem, pet: Pet, userProfile: UserProfile = .default) async -> TaskInPageData {
        // 客户拍板（2026-07-20）：专注页 Tips（encouragement）不要了——App 停止生成、恒发
        // 空串；wire 字段保留占位（0x11 已联调，撤字段代价大于收益），固件收到空串不渲染。
        let overview = await taskOverview(for: task.notes)
        return TaskInPageData(
            taskId: task.id, taskTitle: task.title,
            taskDescription: overview,
            encouragement: ""
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
    static let taskDescriptionByteBudget = DayPackTextBudget.taskDescription

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

    // MARK: - Settlement quote branch（客户 2026-07-20「页面四 每日总结」）

    /// 客户口径：未全部完成时，日程时间 + 专注时长**超过** 4 小时视为「今天已足够努力，
    /// 只是任务定多了」；不超过则给「日程满时少排任务」的固定建议。
    nonisolated static let overloadedDayThresholdMinutes = 240

    /// 客户口径：当日专注累计**超过** 2 小时时，每日总结概况必须提到专注时长。
    nonisolated static let focusMentionThresholdMinutes = 120

    /// 人读时长标签："2h 15m" / "2h" / "45m"。供每日总结概况（prompt 事实块与兜底模板）使用。
    nonisolated static func focusDurationLabel(minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let remainder = clamped % 60
        if hours > 0 && remainder > 0 { return "\(hours)h \(remainder)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(remainder)m"
    }

    /// 今日日程时长合计（分钟），供金句分支的 4 小时阈值使用。
    /// 只累计**非全天**事件——全天事件（24h）会一票冲垮阈值，排除；负跨度（脏数据）忽略。
    /// 客户拍板（2026-07-20）：**重叠时段不重复计**——先合并重叠/相接区间再求和
    /// （两个 2-4 点的会各 2h，实占仍是 2h 不是 4h）。
    nonisolated static func scheduledEventMinutes(events: [CalendarEvent]) -> Int {
        let intervals = events
            .filter { !$0.isAllDay && $0.endTime > $0.startTime }
            .map { (start: $0.startTime, end: $0.endTime) }
            .sorted { $0.start < $1.start }
        guard var current = intervals.first else { return 0 }
        var totalSeconds: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                totalSeconds += current.end.timeIntervalSince(current.start)
                current = interval
            }
        }
        totalSeconds += current.end.timeIntervalSince(current.start)
        return Int(totalSeconds / 60)
    }

    /// 「页面四 每日总结」第二行金句/明日鼓励的三个分支。
    public enum SettlementQuoteBranch: Sendable, Equatable {
        /// 日程和任务全部完成 → 庆祝式金句（IP 风格）。
        case celebration
        /// 未全部完成，但日程时间+专注时长 > 4h → IP 风格表达「努力了，只是任务太满」。
        case overloadedDay
        /// 未全部完成且投入 ≤ 4h → 客户指定的固定建议文案（不走 AI）。
        case fullSchedule
    }

    /// 三分支判定。`completed`/`total` 沿用 `settlementCounts` 口径（任务 + 已结束日程）；
    /// `unfinishedEvents` = 今日尚未结束（`endTime > now`）的日程数——客户拍板（2026-07-20）：
    /// 还有未开始/进行中的日程就**不算**「日程和任务全部完成」，不出庆祝语（settlementCounts
    /// 不计未来日程是防清晨误报满分的显示口径，庆祝判定必须额外把它们挡回来）；
    /// `combinedMinutes` = `scheduledEventMinutes` + 今日专注分钟。
    nonisolated static func settlementQuoteBranch(
        completed: Int, total: Int, unfinishedEvents: Int, combinedMinutes: Int
    ) -> SettlementQuoteBranch {
        if total > 0 && completed >= total && unfinishedEvents == 0 { return .celebration }
        if combinedMinutes > overloadedDayThresholdMinutes { return .overloadedDay }
        return .fullSchedule
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

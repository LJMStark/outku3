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

    /// 页面四唯一文案缓存：素材不变时复用，避免重复请求 AI 和无意义的 DayPack 重发。
    private var settlementReviewCache: (key: String, text: String)?

    private init() {}

    public func generateDayPack(
        pet: Pet, tasks: [TaskItem], events: [CalendarEvent],
        weather: Weather, deviceMode: DeviceMode,
        userProfile: UserProfile = .default,
        customCompanions _: [CustomCompanion] = [],
        screenSize: ScreenSize = .fourInch,
        petDialogue: String = ""
    ) async -> DayPack {
        let now = Date()
        let calendar = Calendar.current
        let todayTasks = tasks.filter { $0.isInTodayDisplay(on: now, calendar: calendar) }
        let todayEvents = events
            .filter { calendar.isDate($0.startTime, inSameDayAs: now) }
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
        let (categorized, daySummary) = await (categorizedEvents, generatedDaySummary)

        // 支持性文字（客户 2026-07-28 规格）：每条事件按其类别的生成规则各写一句，随
        // DayPack Events[] 下发，固件在该日程进行中时自行排版展示。必须在分类**之后**——
        // 六条规则是按 category 分派的，分类结果是它的输入。
        let eventSummaries = await EventSupportTextService.shared.withSupportText(categorized)

        // 手动加入 Today 的任务先于自然到期任务；组内再按 priority、dueDate、id 定序。
        // Swift sort 不稳定，保留完整兜底顺序，确保截断到 maxTasks 后结果可复现。
        let topTasks = Self.topTaskSummaries(from: tasks, screenSize: screenSize)

        // 预热按键支持文字：硬件 Overview 只列出这批 topTasks，用户能按到的只可能是其中之一，
        // 提前生成好 `0x11` 响应就是纯缓存读取、零等待。
        //
        // **不 await**：这是纯缓存预热，DayPack 本身不含它的产物。await 会把 60 秒模型超时
        // 加到本轮 sync 上——而 BLESyncCoordinator 是先生成 DayPack、再按指纹决定这轮要不要发，
        // 等于连"决定不发"的轮次也被拖 60 秒。`0x11` 侧本就有同步兜底（见
        // cachedOrFallbackTaskSupportText），预热迟到只是这次按键用模板，不是错。
        Task { await EventSupportTextService.shared.prewarmTaskSupportText(
            taskTitles: topTasks.map(\.title)
        ) }

        // box③ "First up": next upcoming event, else the top (highest-priority) incomplete task.
        let firstUp = Self.firstUpLabel(events: todayEvents, fallbackTaskTitle: topTasks.first?.title)

        let settlementData = await generateSettlementData(tasks: todayTasks, events: todayEvents, pet: pet, userProfile: userProfile)
        // 页面四每日总结：硬件只有一个气泡。完整文案只写 SettlementReview；协议中保留的
        // SettlementQuote 继续发送长度 0，避免改变 1.3.1 DayPack 的字段顺序。
        let tomorrowFirstUp = Self.tomorrowFirstUpLabel(
            tasks: tasks, events: events, now: now, calendar: calendar
        )
        let settlementReview = await cachedSettlementReview(
            events: eventSummaries, todayEvents: todayEvents,
            settlement: settlementData,
            tomorrowFirstUp: tomorrowFirstUp
        )
        return DayPack(
            date: Date(),
            weather: WeatherInfo(from: weather),
            deviceMode: deviceMode,
            focusChallengeEnabled: false,
            petDialogue: bubble,
            daySummary: daySummary,
            firstUp: firstUp,
            settlementReview: settlementReview,
            settlementQuote: "",
            events: eventSummaries,
            topTasks: topTasks,
            settlementData: settlementData
        )
    }

    /// The single source of truth for the task rows shown on hardware Overview. DayPack and the
    /// versioned `0x1B` business acknowledgement must select and order the exact same rows.
    nonisolated static func topTaskSummaries(
        from tasks: [TaskItem],
        screenSize: ScreenSize,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskSummary] {
        tasks
            .filter { $0.isInTodayDisplay(on: date, calendar: calendar) && !$0.isCompleted }
            .sorted {
                let lhsManual = $0.isManuallySelectedForToday(on: date, calendar: calendar)
                let rhsManual = $1.isManuallySelectedForToday(on: date, calendar: calendar)
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
            .map(TaskSummary.init(from:))
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

    /// 页面四唯一文案。AI 只生成今日回顾；结尾由本地规则确定：明天有安排时提最早一项并
    /// 鼓励，没有安排时用固定金句。最终合成后写入 SettlementReview。
    /// key 含事件类别：异步分类晚到（缓存 miss → 下轮 AI 结果落地）时会重新生成——与
    /// Category 进指纹的既有约定同一逻辑，保证死线事件"必提"不被过期缓存吞掉。
    private func cachedSettlementReview(
        events: [EventSummary], todayEvents: [CalendarEvent],
        settlement: SettlementData,
        tomorrowFirstUp: String
    ) async -> String {
        let overflowDeadlineTitles = Self.overflowDeadlineTitles(events: todayEvents)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: Date()) + "#"
            + events.map { "\($0.time)|\($0.title)|\($0.category.rawValue)" }.joined(separator: "\u{1F}")
            + "#\(settlement.tasksCompleted)/\(settlement.tasksTotal)#\(settlement.totalFocusMinutes)"
            + "#\(overflowDeadlineTitles.joined(separator: "|"))"
            + "#tomorrow=\(tomorrowFirstUp)"
        if let cache = settlementReviewCache, cache.key == key { return cache.text }

        let review = await textService.generateSettlementReview(
            events: events, overflowDeadlineTitles: overflowDeadlineTitles,
            focusMinutes: settlement.totalFocusMinutes,
            tasksCompleted: settlement.tasksCompleted, tasksTotal: settlement.tasksTotal
        )
        let ending = Self.settlementEnding(tomorrowFirstUp: tomorrowFirstUp)
        let result = Self.mergedSettlementReview(
            review: review,
            ending: ending,
            deadlineTitles: events.filter { $0.category == .deadline }.map(\.title)
                + overflowDeadlineTitles,
            focusMinutes: settlement.totalFocusMinutes,
            tasksCompleted: settlement.tasksCompleted,
            tasksTotal: settlement.tasksTotal
        )
        settlementReviewCache = (key, result)
        return result
    }

    public func generateTaskInPage(task: TaskItem, pet: Pet, userProfile: UserProfile = .default) async -> TaskInPageData {
        // 客户 2026-07-28 要求「按按钮进入 task 期间」也显示支持性文字。按按钮进入的是 TaskItem，
        // 而 TaskItem 没有 category 字段（六类只标在日历事件上），客户拍板恒用 Deep Work 规则
        // （"只指向最小的第一步"）。
        //
        // 承载它的是协议 §4.8 里原名 `Encouragement` 的槽位——那是 App 侧的实现选择（复用空槽、
        // 省一次 wire 变更），**不代表「鼓励语 / Tips」功能恢复**：该功能仍按客户 2026-07-20 的
        // 决定停用。字节预算随之 50 → 80B。
        // 支持文字**绝不阻塞这一帧**。设备已经停在任务详情页等 0x11，而无备注时 taskOverview
        // 立即返回——那样支持文字就是唯一的等待，最坏 60 秒（model.requestTimeoutSeconds）白屏。
        // 用缓存命中值，未命中直接取确定性模板：真正的 AI 文案在 sync 时由
        // `prewarmTaskSupportText` 预生成（硬件只能按到 DayPack 下发的 topTasks，见其注释），
        // 所以正常路径按键即命中，冷路径也只降级文案、不降级响应速度。
        let support = EventSupportTextService.shared.cachedOrFallbackTaskSupportText(
            taskTitle: task.title
        )
        let overview = await taskOverview(for: task.notes)
        return TaskInPageData(
            taskId: task.hardwareIdentifier, taskTitle: task.title,
            taskDescription: overview,
            supportText: support
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
        events: [CalendarEvent], fallbackTaskTitle: String?, now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if let next = events.filter({ $0.startTime > now }).min(by: { $0.startTime < $1.startTime }) {
            if next.isAllDay { return next.title }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: next.startTime)) \(next.title)"
        }
        return fallbackTaskTitle ?? ""
    }

    /// 明天最早一项：日历事件优先；没有事件时取明天优先级最高的未完成任务。
    nonisolated static func tomorrowFirstUpLabel(
        tasks: [TaskItem], events: [CalendarEvent], now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
        ) else { return "" }
        let tomorrowEvents = events.filter {
            calendar.isDate($0.startTime, inSameDayAs: tomorrow)
        }
        let taskTitle = tasks
            .filter { $0.isInTodayDisplay(on: tomorrow, calendar: calendar) && !$0.isCompleted }
            .sorted {
                if $0.priority.rawValue != $1.priority.rawValue {
                    return $0.priority.rawValue > $1.priority.rawValue
                }
                let lhsDue = $0.dueDate ?? .distantFuture
                let rhsDue = $1.dueDate ?? .distantFuture
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                return $0.id < $1.id
            }
            .first?.title
        return firstUpLabel(
            events: tomorrowEvents,
            fallbackTaskTitle: taskTitle,
            now: tomorrow.addingTimeInterval(-1),
            calendar: calendar
        )
    }

    /// 单气泡结尾：明天有安排时给明日鼓励；没有安排时沿用已有 IP 金句模板。
    nonisolated static func settlementEnding(
        tomorrowFirstUp: String
    ) -> String {
        let trimmedTomorrow = tomorrowFirstUp.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTomorrow.isEmpty {
            let wireLabel = trimmedTomorrow.asciiSanitizedForEInk()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wireLabel.isEmpty else {
                return "Tomorrow has something waiting. You've got this."
            }
            let label = CompanionTextService.enforceByteBudget(wireLabel, maxBytes: 40)
            return "Tomorrow: \(label). You've got this."
        }

        return FallbackText.settlementClosingQuote()
    }

    /// 合并成硬件唯一总结字段。优先保留结尾；若 AI 回顾在截短后丢失死线/专注硬规则，使用
    /// 预算感知的确定性回顾，保证最终字符串不超过 SettlementReview 的 180B。
    nonisolated static func mergedSettlementReview(
        review: String,
        ending: String,
        deadlineTitles: [String],
        focusMinutes: Int,
        tasksCompleted: Int,
        tasksTotal: Int
    ) -> String {
        let normalizedEnding = CompanionTextService.enforceByteBudget(
            ending.asciiSanitizedForEInk().replacingOccurrences(of: "\n", with: " "),
            maxBytes: 72
        )
        let separatorBytes = normalizedEnding.isEmpty ? 0 : 1
        let reviewBudget = max(
            0,
            DayPackTextBudget.settlementReview - normalizedEnding.utf8.count - separatorBytes
        )
        let normalizedReview = review.asciiSanitizedForEInk()
            .replacingOccurrences(of: "\n", with: " ")
        let compactReview = CompanionTextService.enforceByteBudget(
            normalizedReview, maxBytes: reviewBudget
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = [compactReview, normalizedEnding]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if CompanionTextService.reviewSatisfiesHardRules(
            candidate, deadlineTitles: deadlineTitles, focusMinutes: focusMinutes
        ) {
            return candidate
        }
        return FallbackText.settlementReviewWithEnding(
            deadlineTitles: deadlineTitles,
            focusMinutes: focusMinutes,
            tasksCompleted: tasksCompleted,
            tasksTotal: tasksTotal,
            ending: normalizedEnding
        )
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
        // v2.5.32（审核修正）：分母含**全部**今日日程，分子仍只计已结束——4 个日程过了 1 个
        // 显示 1/4（客户 mock 的 50% 中间态语义），清晨为 0/N 而非旧口径的 0/0→白天恒 100%。
        // "防清晨误显 Perfect day"的原始动机在**分子**（未发生不算完成），不受本次影响；
        // 日终全部结束后 completed == total，与客户"未取消即视为完成"的结算口径一致。
        return (completed: completedTasks + occurredEvents,
                total: tasks.count + events.count)
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
            .map { event -> (start: Date, end: Date) in
                // v2.5.32: 跨午夜日程裁剪到开始日当天——23:00-次日08:00 只给"今天"计 1 小时，
                // 不把 9 小时灌进 4h 阈值（次日部分归次日口径，当前不重复计）。
                let calendar = Calendar.current
                let dayEnd = calendar.date(
                    byAdding: .day, value: 1, to: calendar.startOfDay(for: event.startTime)
                ) ?? event.endTime
                return (event.startTime, min(event.endTime, dayEnd))
            }
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

    /// wire 只带前 8 条事件；第 9 条起用关键词启发式补死线检测（v2.5.32，复审修订：
    /// **标题+描述一起看**——标题 "Q3 filing" 描述 "Final submission due today" 也要命中）。
    /// 纯函数便于直接单测发现过程（不依赖 AI/存储）。
    nonisolated static func overflowDeadlineTitles(events: [CalendarEvent]) -> [String] {
        events.dropFirst(8)
            .filter { EventCategory.heuristic(for: "\($0.title) \($0.description ?? "")") == .deadline }
            .map(\.title)
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

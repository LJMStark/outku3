import Foundation

// MARK: - Focus Statistics

extension FocusSessionService {
    /// 换日后重算统计缓存；同日或从未计算过为 no-op。只应在非渲染时机调用（回前台等），
    /// 渲染路径读 Today 用 `todayFocusTimeIncludingActive(now:)`（纯读不改缓存）。
    public func refreshStatisticsIfDayChanged(now: Date = Date()) {
        guard let referenceDay = statisticsReferenceDay,
              !Calendar.current.isDate(now, inSameDayAs: referenceDay) else { return }
        updateStatistics(now: now)
    }

    /// 专注页 Today 行口径：按 now 判日的今日已结算时长 + 当前活跃会话整段可计时长。
    /// 整段按 endTime 归属（与 updateStatistics 口径一致）：若现在结束即整体归今天，
    /// 因此不做午夜切分，避免结算瞬间总数跳变。纯函数，渲染路径安全。
    public func todayFocusTimeIncludingActive(now: Date = Date()) -> TimeInterval {
        let calendar = Calendar.current
        let settledToday = todaySessions
            .filter { session in
                guard let endTime = session.endTime else { return false }
                return calendar.isDate(endTime, inSameDayAs: now)
            }
            .compactMap(\.calculatedFocusTime)
            .reduce(0, +)
        return settledToday + progressSnapshot(now: now).countableFocusTime
    }

    func updateStatistics(now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        statisticsReferenceDay = today

        let todayCompletedSessions = todaySessions.filter { session in
            guard let endTime = session.endTime else { return false }
            return calendar.isDate(endTime, inSameDayAs: today)
        }

        let focusTimes = todayCompletedSessions.compactMap { $0.calculatedFocusTime }
        let todayFocusTime = focusTimes.reduce(0, +)
        let protectedSessionCount = todayCompletedSessions.filter {
            $0.protectionState == .protected
        }.count

        let averageMinutes = focusTimes.isEmpty
            ? 0
            : Int(focusTimes.reduce(0, +) / Double(focusTimes.count) / 60)
        let longestMinutes = Int((focusTimes.max() ?? 0) / 60)
        let interruptions = todayCompletedSessions.reduce(0) {
            $0 + $1.screenUnlockEvents.count
        }
        let peakHour = computePeakFocusHour(
            sessions: todayCompletedSessions,
            calendar: calendar
        )

        statistics = FocusStatistics(
            todayFocusTime: todayFocusTime,
            todaySessions: todayCompletedSessions.count,
            protectedSessionCount: protectedSessionCount,
            averageSessionMinutes: averageMinutes,
            longestSessionMinutes: longestMinutes,
            interruptionCount: interruptions,
            peakFocusHour: peakHour,
            focusTrendDirection: .stable
        )

        Task {
            async let trend = computeTrendDirection()
            async let historicalTimes = computeHistoricalFocusTimes()
            let (resolvedTrend, (week, month)) = await (trend, historicalTimes)
            statistics.focusTrendDirection = resolvedTrend
            statistics.pastWeekFocusTime = week
            statistics.last30DaysFocusTime = month
        }
    }

    private func computeHistoricalFocusTimes() async -> (
        week: TimeInterval,
        month: TimeInterval
    ) {
        guard persistenceEnabled else { return (0, 0) }
        do {
            let monthSessions = try await localStorage.loadFocusSessionsForPastDays(30)
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            let cutoff7 = calendar.date(
                byAdding: .day,
                value: -7,
                to: startOfToday
            ) ?? .distantPast
            let week = monthSessions
                .filter { $0.startTime >= cutoff7 }
                .compactMap(\.calculatedFocusTime)
                .reduce(0, +)
            let month = monthSessions
                .compactMap(\.calculatedFocusTime)
                .reduce(0, +)
            return (week, month)
        } catch {
            return (0, 0)
        }
    }

    private func computePeakFocusHour(
        sessions: [FocusSession],
        calendar: Calendar
    ) -> Int? {
        guard !sessions.isEmpty else { return nil }

        var hourBuckets: [Int: TimeInterval] = [:]
        for session in sessions {
            guard let focusTime = session.calculatedFocusTime, focusTime > 0 else { continue }
            let hour = calendar.component(.hour, from: session.startTime)
            hourBuckets[hour, default: 0] += focusTime
        }

        return hourBuckets.max(by: { $0.value < $1.value })?.key
    }

    private func computeTrendDirection() async -> TrendDirection {
        guard persistenceEnabled else { return .stable }

        let calendar = Calendar.current
        guard let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: Date())
        ) else {
            return .stable
        }

        do {
            let yesterdaySessions = try await localStorage.loadFocusSessionsForDate(yesterday) ?? []
            let yesterdayFocusTime = yesterdaySessions
                .compactMap(\.calculatedFocusTime)
                .reduce(0, +)

            guard yesterdayFocusTime > 0 else {
                return statistics.todayFocusTime > 0 ? .up : .stable
            }

            let ratio = statistics.todayFocusTime / yesterdayFocusTime
            if ratio > 1.1 { return .up }
            if ratio < 0.9 { return .down }
            return .stable
        } catch {
            return .stable
        }
    }

    /// 生成注意力镜像摘要
    public func generateAttentionSummary() -> AttentionSummary {
        AttentionSummary(
            totalFocusMinutes: Int(statistics.todayFocusTime / 60),
            sessionCount: statistics.todaySessions,
            longestSessionMinutes: statistics.longestSessionMinutes,
            interruptionCount: statistics.interruptionCount,
            peakHour: statistics.peakFocusHour,
            trend: statistics.focusTrendDirection
        )
    }
}

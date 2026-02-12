import Foundation

// MARK: - Reminder Reason

public enum ReminderReason: String, Codable, Sendable {
    case idle           // 长时间未互动
    case deadline       // 任务即将到期
    case streakProtect  // 连续天数保护
    case gentleNudge    // 温和提醒
}

// MARK: - Reminder Urgency

public enum ReminderUrgency: UInt8, Sendable {
    case gentle = 0x00
    case urgent = 0x01
    case streakProtect = 0x02
}

// MARK: - Smart Reminder Result

public struct SmartReminderResult: Sendable {
    public let reason: ReminderReason
    public let urgency: ReminderUrgency
    public let text: String
    public let taskTitle: String?

    public init(reason: ReminderReason, urgency: ReminderUrgency, text: String, taskTitle: String? = nil) {
        self.reason = reason
        self.urgency = urgency
        self.text = text
        self.taskTitle = taskTitle
    }
}

// MARK: - Smart Reminder Service

/// 智能提醒服务 - 根据用户行为上下文推送提醒到 E-ink 设备
@Observable
@MainActor
public final class SmartReminderService {
    public static let shared = SmartReminderService()

    // MARK: - Dependencies

    private let companionText = CompanionTextService.shared
    private let focusService = FocusSessionService.shared
    private let behaviorAnalyzer = BehaviorAnalyzer()

    // MARK: - Rate Limiting

    private var lastReminderTime: Date?
    private let minimumInterval: TimeInterval = 30 * 60 // 30 minutes

    // MARK: - Constants

    private enum Constants {
        static let idleThresholdHours: Int = 2
        static let deadlineThresholdHours: Int = 3
        static let streakProtectMinDays: Int = 3
        static let streakProtectHour: Int = 18
        static let nudgeCooldownMinutes: Int = 60
    }

    private init() {}

    // MARK: - Core Evaluation
    /// 评估当前状态并在满足条件时生成提醒
    public func evaluateAndPushReminder(
        tasks: [TaskItem],
        streak: Streak,
        pet: Pet,
        userProfile: UserProfile = .default
    ) async -> SmartReminderResult? {
        guard canSendReminder() else { return nil }

        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let incompleteTasks = tasks.filter { !$0.isCompleted }
        let completedToday = tasks.filter(\.isCompleted).count

        let summary = behaviorAnalyzer.generateSummary(
            tasks: tasks,
            focusSessions: focusService.todaySessions,
            streak: streak
        )
        let workHours = summary.preferredWorkHours
        let isWorkHours = currentHour >= workHours.start && currentHour < workHours.end

        // 1. Deadline reminder (urgent)
        if let result = await checkDeadline(
            tasks: incompleteTasks, pet: pet, userProfile: userProfile,
            streak: streak, now: now
        ) {
            markReminderSent()
            return result
        }

        // 2. Streak protection
        if let result = await checkStreakProtect(
            streak: streak, completedToday: completedToday,
            currentHour: currentHour, pet: pet, userProfile: userProfile
        ) {
            markReminderSent()
            return result
        }

        // 3. Idle reminder
        if let result = await checkIdle(
            isWorkHours: isWorkHours, incompleteTasks: incompleteTasks,
            pet: pet, userProfile: userProfile, streak: streak
        ) {
            markReminderSent()
            return result
        }

        // 4. Gentle nudge
        if let result = await checkGentleNudge(
            isWorkHours: isWorkHours, incompleteTasks: incompleteTasks,
            pet: pet, userProfile: userProfile, streak: streak
        ) {
            markReminderSent()
            return result
        }

        return nil
    }

    // MARK: - Rate Limiting

    private func canSendReminder() -> Bool {
        guard let last = lastReminderTime else { return true }
        return Date().timeIntervalSince(last) >= minimumInterval
    }

    private func markReminderSent() {
        lastReminderTime = Date()
    }
    // MARK: - Trigger Checks

    /// 高优先级任务今天到期且剩余不足3小时
    private func checkDeadline(
        tasks: [TaskItem], pet: Pet, userProfile: UserProfile,
        streak: Streak, now: Date
    ) async -> SmartReminderResult? {
        let calendar = Calendar.current
        let thresholdDate = calendar.date(byAdding: .hour, value: Constants.deadlineThresholdHours, to: now) ?? now

        let urgentTask = tasks.first { task in
            guard let dueDate = task.dueDate,
                  task.priority == .high,
                  calendar.isDateInToday(dueDate),
                  dueDate <= thresholdDate else { return false }
            return true
        }

        guard let task = urgentTask else { return nil }

        let text = await companionText.generateSmartReminder(
            reason: .deadline, petName: pet.name, petMood: pet.mood,
            taskTitle: task.title, streakDays: streak.currentStreak,
            userProfile: userProfile
        )
        return SmartReminderResult(reason: .deadline, urgency: .urgent, text: text, taskTitle: task.title)
    }

    /// 连续天数>3天 且 今天未完成任务 且 18:00后
    private func checkStreakProtect(
        streak: Streak, completedToday: Int, currentHour: Int,
        pet: Pet, userProfile: UserProfile
    ) async -> SmartReminderResult? {
        guard streak.currentStreak > Constants.streakProtectMinDays,
              completedToday == 0,
              currentHour >= Constants.streakProtectHour else { return nil }

        let text = await companionText.generateSmartReminder(
            reason: .streakProtect, petName: pet.name, petMood: pet.mood,
            taskTitle: nil, streakDays: streak.currentStreak,
            userProfile: userProfile
        )
        return SmartReminderResult(reason: .streakProtect, urgency: .streakProtect, text: text)
    }

    /// 工作时间内超过2小时无互动
    private func checkIdle(
        isWorkHours: Bool, incompleteTasks: [TaskItem],
        pet: Pet, userProfile: UserProfile, streak: Streak
    ) async -> SmartReminderResult? {
        guard isWorkHours, !incompleteTasks.isEmpty else { return nil }

        let sessions = focusService.todaySessions
        let lastActivity: Date? = sessions.last?.endTime ?? sessions.last?.startTime
        let idleThreshold = TimeInterval(Constants.idleThresholdHours * 3600)

        if let last = lastActivity, Date().timeIntervalSince(last) < idleThreshold {
            return nil
        } else if lastActivity == nil {
            let workStart = Calendar.current.date(
                bySettingHour: 9, minute: 0, second: 0, of: Date()
            ) ?? Date()
            guard Date().timeIntervalSince(workStart) >= idleThreshold else {
                return nil
            }
        }

        let text = await companionText.generateSmartReminder(
            reason: .idle, petName: pet.name, petMood: pet.mood,
            taskTitle: incompleteTasks.first?.title, streakDays: streak.currentStreak,
            userProfile: userProfile
        )
        return SmartReminderResult(reason: .idle, urgency: .gentle, text: text)
    }

    /// 工作时间内有未完成任务且上次专注结束超过1小时
    private func checkGentleNudge(
        isWorkHours: Bool, incompleteTasks: [TaskItem],
        pet: Pet, userProfile: UserProfile, streak: Streak
    ) async -> SmartReminderResult? {
        guard isWorkHours, !incompleteTasks.isEmpty else { return nil }

        let sessions = focusService.todaySessions
        guard let lastEnd = sessions.last?.endTime else { return nil }

        let cooldown = TimeInterval(Constants.nudgeCooldownMinutes * 60)
        guard Date().timeIntervalSince(lastEnd) >= cooldown else { return nil }

        let text = await companionText.generateSmartReminder(
            reason: .gentleNudge, petName: pet.name, petMood: pet.mood,
            taskTitle: incompleteTasks.first?.title, streakDays: streak.currentStreak,
            userProfile: userProfile
        )
        return SmartReminderResult(reason: .gentleNudge, urgency: .gentle, text: text)
    }
}

import Foundation

// MARK: - Task Dehydration Service

/// AI 任务分解服务 - 基于 Implementation Intentions 理论将任务拆解为 What/When/Why 微行动
@MainActor
public final class TaskDehydrationService {
    public static let shared = TaskDehydrationService()

    private let openAI = OpenAIService.shared
    private let localStorage = LocalStorage.shared

    private static let cacheExpiry: TimeInterval = 24 * 60 * 60

    private init() {}

    // MARK: - Core Dehydration

    /// Decompose a task into micro-actions using AI (with cache and fallback)
    public func dehydrate(
        task: TaskItem,
        schedule: [CalendarEvent],
        userProfile: UserProfile = .default
    ) async -> [MicroAction] {
        if let cached = await loadCachedActions(for: task) {
            return cached
        }

        guard await openAI.isConfigured else {
            return [fallbackAction(for: task)]
        }

        let slots = findAvailableSlots(
            schedule: schedule,
            workHours: WorkHourRange()
        )
        let slotStrings = slots.map(\.description)

        do {
            let json = try await openAI.dehydrateTask(
                taskTitle: task.title,
                availableSlots: slotStrings,
                userProfile: userProfile
            )
            let actions = parseActions(from: json)
            let result = actions.isEmpty ? [fallbackAction(for: task)] : actions
            await cacheActions(result, for: task)
            return result
        } catch {
            #if DEBUG
            print("[TaskDehydration] AI call failed: \(error.localizedDescription)")
            #endif
            return [fallbackAction(for: task)]
        }
    }
    // MARK: - Parsing

    private func parseActions(from json: String) -> [MicroAction] {
        guard let data = json.data(using: .utf8) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([DehydratedAction].self, from: data)
            return Array(decoded.prefix(5)).map { action in
                MicroAction(
                    what: String(action.what.prefix(40)),
                    when: action.when,
                    why: action.why.map { String($0.prefix(60)) },
                    estimatedMinutes: action.estimatedMinutes
                )
            }
        } catch {
            return []
        }
    }

    private struct DehydratedAction: Codable {
        let what: String
        let when: String?
        let why: String?
        let estimatedMinutes: Int?
    }

    // MARK: - Fallback

    private func fallbackAction(for task: TaskItem) -> MicroAction {
        MicroAction(what: String(task.title.prefix(40)), when: nil, why: nil, estimatedMinutes: nil)
    }

    // MARK: - Cache

    private func loadCachedActions(for task: TaskItem) async -> [MicroAction]? {
        do {
            guard let cached = try await localStorage.loadDehydrationCache(taskId: task.id) else {
                return nil
            }
            guard Date().timeIntervalSince(cached.cachedAt) < Self.cacheExpiry else {
                return nil
            }
            guard cached.taskTitle == task.title else {
                return nil
            }
            return cached.actions
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "dehydration_cache_\(task.id).json", underlying: error.localizedDescription),
                context: "TaskDehydrationService.loadCachedActions"
            )
            return nil
        }
    }

    private func cacheActions(_ actions: [MicroAction], for task: TaskItem) async {
        do {
            let cached = DehydrationCache(taskTitle: task.title, actions: actions, cachedAt: Date())
            try await localStorage.saveDehydrationCache(cached, taskId: task.id)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "save", target: "dehydration_cache_\(task.id).json", underlying: error.localizedDescription),
                context: "TaskDehydrationService.cacheActions"
            )
        }
    }

    // MARK: - Schedule Gap Analysis

    private func findAvailableSlots(
        schedule: [CalendarEvent],
        workHours: WorkHourRange
    ) -> [TimeSlot] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        guard let workStart = calendar.date(bySettingHour: workHours.start, minute: 0, second: 0, of: today),
              let workEnd = calendar.date(bySettingHour: workHours.end, minute: 0, second: 0, of: today) else {
            return []
        }

        let effectiveStart = max(now, workStart)
        guard effectiveStart < workEnd else { return [] }

        let todayEvents = schedule
            .filter { calendar.isDateInToday($0.startTime) }
            .sorted { $0.startTime < $1.startTime }

        var slots: [TimeSlot] = []
        var cursor = effectiveStart

        for event in todayEvents {
            if event.startTime > cursor {
                let gap = event.startTime.timeIntervalSince(cursor)
                if gap >= 30 * 60 {
                    slots.append(TimeSlot(start: cursor, end: event.startTime))
                }
            }
            let eventEnd = event.endTime
            cursor = max(cursor, eventEnd)
        }

        if cursor < workEnd {
            slots.append(TimeSlot(start: cursor, end: workEnd))
        }

        return slots
    }
}

// MARK: - Supporting Types

public struct TimeSlot: Sendable {
    public let start: Date
    public let end: Date

    public var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

public struct DehydrationCache: Codable, Sendable {
    public let taskTitle: String
    public let actions: [MicroAction]
    public let cachedAt: Date
}

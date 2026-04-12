import Foundation

struct CompanionDialogueTriggerState {
    let fingerprint: String
    let context: AIContext
}

private enum PetDialogueState {
    case morningPrep
    case inTask
    case scheduleEvent
    case daySettled
    case idle
}

extension AppState {
    func refreshHomeCompanionPresentation(now: Date = Date()) async {
        let todayKey = Self.homeCompanionDateKey(from: now)
        currentPetDialogue = await loadCachedSharedPetDialogue(for: todayKey) ?? ""

        guard await shouldShowDailyHaiku(on: todayKey) else {
            homeCompanionDisplayMode = .petDialogue
            return
        }

        homeCompanionDisplayMode = .dailyHaiku
        await loadTodayHaiku(now: now)
        guard !Task.isCancelled else { return }
        await localStorage.saveLastHomeHaikuShownDate(todayKey)
    }

    func switchHomeToPetDialogue() {
        homeCompanionDisplayMode = .petDialogue
    }

    private func loadCachedSharedPetDialogue(for todayKey: String) async -> String? {
        guard let cached = try? await localStorage.loadSharedCompanionDialogue(),
              cached.date == todayKey else {
            return nil
        }

        let normalized = CompanionDialogueDisplayPolicy.normalized(cached.text)
        guard CompanionDialogueDisplayPolicy.isValidForDisplay(normalized) else {
            return nil
        }

        return normalized
    }

    private func shouldShowDailyHaiku(on todayKey: String) async -> Bool {
        await localStorage.loadLastHomeHaikuShownDate() != todayKey
    }

    func refreshSharedPetDialogueIfNeeded(force: Bool = false) async {
        let triggerState = await buildCompanionDialogueTriggerState()
        let todayKey = Self.homeCompanionDateKey(from: triggerState.context.currentTime)

        if !force,
           let cached = try? await localStorage.loadSharedCompanionDialogue(),
           cached.date == todayKey,
           cached.fingerprint == triggerState.fingerprint {
            let normalized = CompanionDialogueDisplayPolicy.normalized(cached.text)
            if CompanionDialogueDisplayPolicy.isValidForDisplay(normalized) {
                currentPetDialogue = normalized
                return
            }
        }

        let phase = resolveCompanionPhase(triggerState: triggerState)
        let aiType: AITextType
        switch phase {
        case .morningPrep: aiType = .morningGreeting
        case .inTask: aiType = .taskEncouragement
        case .scheduleEvent: aiType = .scheduleReminder
        case .daySettled: aiType = .settlementSummary
        case .idle: aiType = .smartReminder
        }

        let dialogue = await CompanionTextService.shared.generateSharedPetDialogue(
            baseContext: triggerState.context,
            type: aiType
        )
        currentPetDialogue = dialogue

        do {
            try await localStorage.saveSharedCompanionDialogue(
                SharedCompanionDialogueCache(
                    date: todayKey,
                    fingerprint: triggerState.fingerprint,
                    text: dialogue
                )
            )
        } catch {
            reportPersistenceError(error, operation: "save", target: "shared_companion_dialogue.json")
        }
    }

    private func resolveCompanionPhase(triggerState: CompanionDialogueTriggerState) -> PetDialogueState {
        let context = triggerState.context

        if FocusSessionService.shared.activeSession != nil {
            return .inTask
        }

        if let next = context.nextAgendaItem, next.starts(with: "Now · ") {
            return .scheduleEvent
        }

        let isEveningOrNight = TimeOfDay.current(at: context.currentTime) == .evening || TimeOfDay.current(at: context.currentTime) == .night
        let allCompleted = context.totalTasksToday > 0 && context.tasksCompletedToday >= context.totalTasksToday

        if allCompleted || (isEveningOrNight && context.totalTasksToday > 0) {
            return .daySettled
        }

        if TimeOfDay.current(at: context.currentTime) == .morning && context.tasksCompletedToday == 0 {
            return .morningPrep
        }

        return .idle
    }

    func buildCompanionDialogueTriggerState(at now: Date = Date()) async -> CompanionDialogueTriggerState {
        let activeTask = Self.resolveActiveTask(
            activeSession: FocusSessionService.shared.activeSession,
            tasks: tasks
        )
        let todayTasks = tasksForToday()
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted && rhs.isCompleted
                }
                if lhs.priority != rhs.priority {
                    return lhs.priority.rawValue > rhs.priority.rawValue
                }
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
        let todayEvents = events
            .filter { Calendar.current.isDateInToday($0.startTime) }
            .sorted { $0.startTime < $1.startTime }
        let topTaskTitles = todayTasks
            .filter { !$0.isCompleted }
            .prefix(3)
            .map(\.title)
        let todayProgress = Self.companionTaskProgressSnapshot(from: todayTasks)
        let nextAgendaItem = companionNextAgendaItem(from: todayEvents, fallbackTasks: topTaskTitles, now: now)
        let focusMinutes = Int(FocusSessionService.shared.statistics.todayFocusTime / 60)
        let energyBottles = await localStorage.loadEnergyBottles()
        let currentSceneName = SceneUnlockService.shared.currentSceneId(energyBottles: energyBottles)
        let learnText = PromptDebuggerState.shared.testLearnText.trimmingCharacters(in: .whitespacesAndNewlines)

        let context = AIContext(
            companionStyle: userProfile.companionStyle,
            companionCharacter: userProfile.companionCharacter,
            intimacyStage: userProfile.intimacyStage,
            workType: userProfile.workType,
            primaryGoals: userProfile.primaryGoals,
            petName: pet.name,
            petMood: pet.mood,
            currentTime: now,
            tasksCompletedToday: todayProgress.completed,
            totalTasksToday: todayProgress.total,
            eventsToday: todayEvents.count,
            currentStreak: streak.currentStreak,
            recentCompletionRate: todayProgress.rate,
            focusTimeToday: focusMinutes,
            energyBottles: energyBottles,
            currentSceneName: currentSceneName,
            hardwareConnected: BLEService.shared.connectionState.isConnected,
            nextAgendaItem: nextAgendaItem,
            activeTaskTitle: activeTask.taskTitle,
            topTaskTitles: topTaskTitles,
            userDefinedLearnText: learnText.isEmpty ? nil : learnText
        )

        let activeTaskId = activeTask.taskId ?? ""

        return CompanionDialogueTriggerState(
            fingerprint: companionDialogueFingerprint(
                now: now,
                todayTasks: todayTasks,
                todayEvents: todayEvents,
                topTaskTitles: topTaskTitles,
                nextAgendaItem: nextAgendaItem,
                focusMinutes: focusMinutes,
                energyBottles: energyBottles,
                sceneId: currentSceneName,
                activeTaskId: activeTaskId,
                activeTaskTitle: activeTask.taskTitle,
                learnText: context.userDefinedLearnText
            ),
            context: context
        )
    }

    private func companionDialogueFingerprint(
        now: Date,
        todayTasks: [TaskItem],
        todayEvents: [CalendarEvent],
        topTaskTitles: [String],
        nextAgendaItem: String?,
        focusMinutes: Int,
        energyBottles: Int,
        sceneId: String,
        activeTaskId: String,
        activeTaskTitle: String?,
        learnText: String?
    ) -> String {
        let todayProgress = Self.companionTaskProgressSnapshot(from: todayTasks)

        var parts: [String] = [
            "date=\(Self.homeCompanionDateKey(from: now))",
            "bucket=\(TimeOfDay.current(at: now).rawValue)",
            "style=\(userProfile.companionStyle.rawValue)",
            "character=\(userProfile.companionCharacter.rawValue)",
            "intimacy=\(userProfile.intimacyStage.rawValue)",
            "work=\(userProfile.workType.rawValue)",
            "goals=\(userProfile.primaryGoals.map(\.rawValue).joined(separator: ","))",
            "petMood=\(pet.mood.rawValue)",
            "petScene=\(sceneId)",
            "streak=\(streak.currentStreak)",
            "todayCompleted=\(todayProgress.completed)",
            "todayTotal=\(todayProgress.total)",
            "eventsToday=\(todayEvents.count)",
            "focusMinutes=\(focusMinutes)",
            "energyBottles=\(energyBottles)",
            "activeTask=\(activeTaskId)",
            "activeTaskTitle=\(activeTaskTitle ?? "")",
            "nextAgenda=\(nextAgendaItem ?? "")",
            "topTasks=\(topTaskTitles.joined(separator: "|"))",
            "promptVersion=\(OpenAIService.companionPromptVersion)",
            "learn=\(learnText ?? "")"
        ]

        for task in todayTasks {
            let dueText = task.dueDate.map { Self.dialogueTimeFormatter.string(from: $0) } ?? ""
            parts.append("task=\(task.id)|\(task.title)|\(task.isCompleted ? 1 : 0)|\(task.priority.rawValue)|\(dueText)")
        }

        for event in todayEvents {
            parts.append(
                "event=\(event.id)|\(event.title)|\(Int(event.startTime.timeIntervalSince1970))|\(Int(event.endTime.timeIntervalSince1970))"
            )
        }

        return parts.joined(separator: "||")
    }

    private func companionNextAgendaItem(
        from todayEvents: [CalendarEvent],
        fallbackTasks: [String],
        now: Date
    ) -> String? {
        if let currentEvent = todayEvents.first(where: { $0.startTime <= now && $0.endTime >= now }) {
            return "Now · \(currentEvent.title)"
        }

        if let nextEvent = todayEvents.first(where: { $0.startTime > now }) {
            return "\(Self.dialogueTimeFormatter.string(from: nextEvent.startTime)) · \(nextEvent.title)"
        }

        if let firstTask = fallbackTasks.first {
            return "Task · \(firstTask)"
        }

        return nil
    }

    static func companionTaskProgressSnapshot(from todayTasks: [TaskItem]) -> (completed: Int, total: Int, rate: Double) {
        let completed = todayTasks.filter(\.isCompleted).count
        let total = todayTasks.count
        let rate = total > 0 ? Double(completed) / Double(total) : 0
        return (completed, total, rate)
    }

    nonisolated static func resolveActiveTask(
        activeSession: FocusSession?,
        tasks: [TaskItem]
    ) -> (taskId: String?, taskTitle: String?) {
        guard let activeSession else {
            return (nil, nil)
        }

        if let taskTitle = resolveLatestTask(taskId: activeSession.taskId, in: tasks)?.title {
            return (activeSession.taskId, taskTitle)
        }

        if let latestIncompleteTask = latestIncompleteTask(in: tasks) {
            return (latestIncompleteTask.id, latestIncompleteTask.title)
        }

        let taskTitle = activeSession.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return (activeSession.taskId, taskTitle.isEmpty ? nil : taskTitle)
    }

    nonisolated static func resolveLatestTask(taskId: String, in tasks: [TaskItem]) -> TaskItem? {
        tasks
            .filter { $0.id == taskId }
            .max { lhs, rhs in
                let lhsRecency = taskRecency(lhs)
                let rhsRecency = taskRecency(rhs)
                if lhsRecency == rhsRecency {
                    return lhs.lastModified < rhs.lastModified
                }
                return lhsRecency < rhsRecency
            }
    }

    nonisolated static func taskRecency(_ task: TaskItem) -> Date {
        guard let remoteUpdatedAt = task.remoteUpdatedAt else {
            return task.lastModified
        }
        return max(remoteUpdatedAt, task.lastModified)
    }

    /// Returns true if the task was modified locally by the user (not just refreshed by sync).
    /// When Google/Apple sync runs, it sets `lastModified = remoteUpdatedAt`, making them equal.
    /// A local user edit sets `lastModified = Date()` which diverges from `remoteUpdatedAt`.
    nonisolated static func isLocallyModified(_ task: TaskItem) -> Bool {
        guard let remoteUpdatedAt = task.remoteUpdatedAt else {
            return true // No remote timestamp means it was created locally
        }
        // Allow 1-second tolerance for floating-point date comparison
        return abs(task.lastModified.timeIntervalSince(remoteUpdatedAt)) > 1.0
    }

    /// Pick the most relevant incomplete task for encouragement.
    /// Priority: locally-modified tasks first, then by lastModified desc.
    /// Filters out completed and pendingDeletion tasks.
    nonisolated static func latestIncompleteTask(in tasks: [TaskItem]) -> TaskItem? {
        tasks
            .filter { !$0.isCompleted && !$0.pendingDeletion }
            .max { lhs, rhs in
                let lhsLocal = isLocallyModified(lhs)
                let rhsLocal = isLocallyModified(rhs)
                // Locally-modified tasks always rank above sync-only tasks
                if lhsLocal != rhsLocal {
                    return !lhsLocal && rhsLocal
                }
                // Within same category, pick by lastModified (most recent wins)
                return lhs.lastModified < rhs.lastModified
            }
    }

    private static func homeCompanionDateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static let dialogueTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

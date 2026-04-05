import Foundation

private struct CompanionDialogueTriggerState {
    let fingerprint: String
    let context: AIContext
}

private enum PetDialogueState {
    case morningPrep
    case inTask
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

        return cached.text
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
            currentPetDialogue = cached.text
            return
        }

        let phase = resolveCompanionPhase(triggerState: triggerState)
        let aiType: AITextType
        switch phase {
        case .morningPrep: aiType = .morningGreeting
        case .inTask: aiType = .taskEncouragement
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
        
        let activeTaskTitle = FocusSessionService.shared.activeSession?.taskTitle
        if activeTaskTitle != nil {
            return .inTask
        }
        
        if let next = context.nextAgendaItem, next.starts(with: "Now · ") {
            return .inTask
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

    private func buildCompanionDialogueTriggerState(at now: Date = Date()) async -> CompanionDialogueTriggerState {
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
        let nextAgendaItem = companionNextAgendaItem(from: todayEvents, fallbackTasks: topTaskTitles, now: now)
        let focusMinutes = Int(FocusSessionService.shared.statistics.todayFocusTime / 60)
        let energyBlocks = await localStorage.loadEnergyBlocks()
        let learnText = PromptDebuggerState.shared.testLearnText.trimmingCharacters(in: .whitespacesAndNewlines)

        let context = AIContext(
            companionStyle: userProfile.companionStyle,
            workType: userProfile.workType,
            primaryGoals: userProfile.primaryGoals,
            petName: pet.name,
            petMood: pet.mood,
            currentTime: now,
            tasksCompletedToday: statistics.todayCompleted,
            totalTasksToday: statistics.todayTotal,
            eventsToday: todayEvents.count,
            currentStreak: streak.currentStreak,
            recentCompletionRate: statistics.todayPercentage,
            focusTimeToday: focusMinutes,
            energyBlocks: energyBlocks,
            currentSceneName: pet.scene.rawValue,
            hardwareConnected: BLEService.shared.connectionState.isConnected,
            nextAgendaItem: nextAgendaItem,
            topTaskTitles: topTaskTitles,
            userDefinedLearnText: learnText.isEmpty ? nil : learnText
        )

        let activeTaskId = FocusSessionService.shared.activeSession?.taskId ?? ""

        return CompanionDialogueTriggerState(
            fingerprint: companionDialogueFingerprint(
                now: now,
                todayTasks: todayTasks,
                todayEvents: todayEvents,
                topTaskTitles: topTaskTitles,
                nextAgendaItem: nextAgendaItem,
                focusMinutes: focusMinutes,
                energyBlocks: energyBlocks,
                activeTaskId: activeTaskId,
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
        energyBlocks: Int,
        activeTaskId: String,
        learnText: String?
    ) -> String {
        var parts: [String] = [
            "date=\(Self.homeCompanionDateKey(from: now))",
            "bucket=\(TimeOfDay.current(at: now).rawValue)",
            "style=\(userProfile.companionStyle.rawValue)",
            "work=\(userProfile.workType.rawValue)",
            "goals=\(userProfile.primaryGoals.map(\.rawValue).joined(separator: ","))",
            "petMood=\(pet.mood.rawValue)",
            "petScene=\(pet.scene.rawValue)",
            "streak=\(streak.currentStreak)",
            "todayCompleted=\(statistics.todayCompleted)",
            "todayTotal=\(statistics.todayTotal)",
            "eventsToday=\(todayEvents.count)",
            "focusMinutes=\(focusMinutes)",
            "energyBlocks=\(energyBlocks)",
            "activeTask=\(activeTaskId)",
            "nextAgenda=\(nextAgendaItem ?? "")",
            "topTasks=\(topTaskTitles.joined(separator: "|"))",
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

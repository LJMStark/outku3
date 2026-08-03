import Foundation

public struct DailyContentGenerationInput: Sendable {
    public let now: Date
    public let calendar: Calendar
    public let events: [CalendarEvent]
    public let tasks: [TaskItem]
    public let pet: Pet
    public let weather: Weather
    public let deviceMode: DeviceMode
    public let userProfile: UserProfile
    public let customCompanions: [CustomCompanion]
    public let usageDays: Int
    public let sceneID: String
    public let focusMinutes: Int
    public let previousPackage: DailyContentPackage?
    public let previousEventFingerprints: [String: String]
    public let previousPersonaFingerprint: String
    public let previousEventDialogueFingerprint: String
    public let previousStaticCopyFingerprint: String

    public init(
        now: Date,
        calendar: Calendar = .current,
        events: [CalendarEvent],
        tasks: [TaskItem],
        pet: Pet,
        weather: Weather = Weather(),
        deviceMode: DeviceMode = .interactive,
        userProfile: UserProfile,
        customCompanions: [CustomCompanion],
        usageDays: Int,
        sceneID: String,
        focusMinutes: Int = 0,
        previousPackage: DailyContentPackage? = nil,
        previousEventFingerprints: [String: String] = [:],
        previousPersonaFingerprint: String = "",
        previousEventDialogueFingerprint: String = "",
        previousStaticCopyFingerprint: String = ""
    ) {
        self.now = now
        self.calendar = calendar
        self.events = events
        self.tasks = tasks
        self.pet = pet
        self.weather = weather
        self.deviceMode = deviceMode
        self.userProfile = userProfile
        self.customCompanions = customCompanions
        self.usageDays = usageDays
        self.sceneID = sceneID
        self.focusMinutes = focusMinutes
        self.previousPackage = previousPackage
        self.previousEventFingerprints = previousEventFingerprints
        self.previousPersonaFingerprint = previousPersonaFingerprint
        self.previousEventDialogueFingerprint = previousEventDialogueFingerprint
        self.previousStaticCopyFingerprint = previousStaticCopyFingerprint
    }
}

@MainActor
protocol DailyContentPackagePreparing: AnyObject {
    func prepare(input: DailyContentGenerationInput) async throws -> DailyContentPackage
}

@MainActor
public final class DailyContentPackageGenerator {
    public static let shared = DailyContentPackageGenerator()

    private let preparer: any DailyContentPackagePreparing

    private convenience init() {
        self.init(preparer: LiveDailyContentPackagePreparer())
    }

    init(preparer: any DailyContentPackagePreparing) {
        self.preparer = preparer
    }

    /// A daily package is one all-or-nothing unit. A failed first AI preparation gets one fresh
    /// background attempt. Only after that attempt fails do deterministic templates fill every
    /// slot, so transport never receives a package with missing dialogue.
    public func generate(input: DailyContentGenerationInput) async -> DailyContentPackage {
        do {
            return try await preparer.prepare(input: input)
        } catch {
            Log.ai.warning("Daily content preparation failed once; retrying the complete copy batch")
        }
        do {
            return try await preparer.prepare(input: input)
        } catch {
            Log.ai.warning("Daily content preparation failed twice; using complete local templates")
            return DailyContentFallbackFactory.make(input: input)
        }
    }
}

@MainActor
private final class LiveDailyContentPackagePreparer: DailyContentPackagePreparing {
    private let dayPackGenerator = DayPackGenerator.shared
    private let textService = CompanionTextService.shared
    private let screensaverService = ScreensaverService.shared

    func prepare(input: DailyContentGenerationInput) async throws -> DailyContentPackage {
        let todayEvents = DailyContentSource.todayEvents(
            from: input.events,
            at: input.now,
            calendar: input.calendar
        )
        let eventDialogueFingerprint = DailyContentSource.eventDialogueFingerprint(
            pet: input.pet,
            userProfile: input.userProfile,
            customCompanions: input.customCompanions
        )
        let activeCustomCompanion = input.userProfile.customCompanionId.flatMap { id in
            input.customCompanions.first { $0.id == id }
        }
        let currentStaticCopyFingerprint = DailyContentSource.staticCopyFingerprint(
            eventTitles: todayEvents.map(\.title),
            tasks: input.tasks,
            pet: input.pet,
            usageDays: input.usageDays,
            sceneID: input.sceneID,
            userProfile: input.userProfile,
            customCompanions: input.customCompanions
        )
        let reusableDialogues = input.previousEventDialogueFingerprint
            == eventDialogueFingerprint
            ? input.previousPackage
            : nil
        let reusableScreensaver = input.previousStaticCopyFingerprint
            == currentStaticCopyFingerprint
            ? input.previousPackage
            : nil

        var oldEvents: [String: DailyContentEvent] = [:]
        for event in input.previousPackage?.events ?? [] where oldEvents[event.eventID] == nil {
            oldEvents[event.eventID] = event
        }
        var summariesByIdentity: [String: EventSummary] = [:]
        var changedEvents: [CalendarEvent] = []
        for event in todayEvents {
            let identifier = DailyContentSource.eventIdentifier(event)
            if input.previousEventFingerprints[identifier]
                == DailyContentSource.eventFingerprint(event),
               let old = oldEvents[identifier] {
                summariesByIdentity[identifier] = EventSummary(from: event)
                    .withCategory(old.category)
                    .withSupportText(old.supportText)
            } else {
                changedEvents.append(event)
            }
        }
        if !changedEvents.isEmpty {
            let raw = changedEvents.map { EventSummary(from: $0) }
            let categorized = await EventCategoryService.shared.categorized(raw)
            for (event, summary) in zip(changedEvents, categorized) {
                summariesByIdentity[DailyContentSource.eventIdentifier(event)] = summary
            }
            let densityContext = todayEvents.map { event in
                summariesByIdentity[DailyContentSource.eventIdentifier(event)]
                    ?? EventSummary(from: event).withCategory(.admin)
            }
            let supported = await EventSupportTextService.shared.withSupportText(
                categorized,
                densityContext: densityContext
            )
            for (event, summary) in zip(changedEvents, supported) {
                summariesByIdentity[DailyContentSource.eventIdentifier(event)] = summary
            }
        }
        let preparedSummaries = todayEvents.map { event in
            summariesByIdentity[DailyContentSource.eventIdentifier(event)]
                ?? EventSummary(from: event).withCategory(.admin)
        }

        async let generatedDayPack = dayPackGenerator.generateDayPack(
            pet: input.pet,
            tasks: input.tasks,
            events: todayEvents,
            weather: input.weather,
            deviceMode: input.deviceMode,
            userProfile: input.userProfile,
            customCompanions: input.customCompanions,
            screenSize: .sevenInch,
            petDialogue: "",
            now: input.now,
            calendar: input.calendar,
            preparedEventSummaries: preparedSummaries,
            focusMinutesOverride: input.focusMinutes,
            precomputeEndOfDaySettlement: true
        )
        let staticDialogues: (morning: String, idle: String, closing: String)
        if let reusableDialogues {
            staticDialogues = (
                reusableDialogues.morningDialogue,
                reusableDialogues.idleDialogue,
                reusableDialogues.closingDialogue
            )
        } else {
            async let morning = textService.generateCompanionPhrase(
                petMood: input.pet.mood,
                timeOfDay: .morning,
                userProfile: input.userProfile
            )
            async let idle = textService.generateCompanionPhrase(
                petMood: input.pet.mood,
                timeOfDay: .afternoon,
                userProfile: input.userProfile
            )
            async let closing = textService.generateCompanionPhrase(
                petMood: input.pet.mood,
                timeOfDay: .evening,
                userProfile: input.userProfile
            )
            staticDialogues = await (morning, idle, closing)
        }

        let dayPack = await generatedDayPack
        var dailyEvents: [DailyContentEvent] = []
        dailyEvents.reserveCapacity(todayEvents.count)
        for event in todayEvents {
            let eventID = DailyContentSource.eventIdentifier(event)
            let fingerprint = DailyContentSource.eventFingerprint(event)
            let canReuse = input.previousEventDialogueFingerprint == eventDialogueFingerprint
                && input.previousEventFingerprints[eventID] == fingerprint
            if canReuse, let old = oldEvents[eventID] {
                dailyEvents.append(old)
                continue
            }
            let summary = summariesByIdentity[eventID] ?? EventSummary(from: event)
            let eventDialogue = await textService.generateTaskEncouragement(
                taskTitle: event.title,
                petName: input.pet.name,
                petMood: input.pet.mood,
                userProfile: input.userProfile
            )
            dailyEvents.append(DailyContentSource.makeEvent(
                from: event,
                summary: summary,
                companionDialogue: eventDialogue
            ))
        }

        let screensaver: ScreensaverConfig
        if let reusableScreensaver {
            screensaver = ScreensaverConfig(
                quote: reusableScreensaver.screensaverQuote,
                author: reusableScreensaver.screensaverAuthor
            )
        } else {
            screensaver = await preparedScreensaver(
                input: input,
                events: todayEvents,
                customCompanion: activeCustomCompanion
            )
        }
        return DailyContentPackage(
            localDate: DailyContentDate(date: input.now, calendar: input.calendar),
            morningDialogue: staticDialogues.morning,
            idleDialogue: staticDialogues.idle,
            closingDialogue: staticDialogues.closing,
            daySummary: dayPack.daySummary,
            screensaverQuote: screensaver.quote,
            screensaverAuthor: screensaver.author,
            settlementReview: dayPack.settlementReview,
            settlementQuote: dayPack.settlementQuote,
            events: dailyEvents
        )
    }

    private func preparedScreensaver(
        input: DailyContentGenerationInput,
        events: [CalendarEvent],
        customCompanion: CustomCompanion?
    ) async -> ScreensaverConfig {
        let taskTitles = input.tasks.lazy
            .filter { !$0.isCompleted && !$0.pendingDeletion }
            .map(\.title)
        let eventTitles = events.map(\.title)
        _ = screensaverService.getScreensaverConfig(
            usageDays: input.usageDays,
            currentSceneId: input.sceneID,
            userProfile: input.userProfile,
            topTaskTitles: Array(taskTitles),
            upcomingEventTitles: eventTitles,
            customCompanion: customCompanion
        )
        await screensaverService.waitForPendingGeneration()
        return screensaverService.getScreensaverConfig(
            usageDays: input.usageDays,
            currentSceneId: input.sceneID,
            userProfile: input.userProfile,
            topTaskTitles: Array(taskTitles),
            upcomingEventTitles: eventTitles,
            customCompanion: customCompanion,
            scheduleGeneration: false
        )
    }
}

@MainActor
enum DailyContentFallbackFactory {
    static func make(input: DailyContentGenerationInput) -> DailyContentPackage {
        let events = DailyContentSource.todayEvents(
            from: input.events,
            at: input.now,
            calendar: input.calendar
        )
        let summaries = events.map { event -> EventSummary in
            let raw = EventSummary(from: event)
            let classificationText = raw.description.isEmpty
                ? raw.title
                : "\(raw.title) — \(raw.description)"
            let category = EventCategory.heuristic(for: classificationText)
            return raw.withCategory(category == .unknown ? .admin : category)
        }
        let packed = FallbackText.isDayBusy(summaries)
        let dailyEvents = zip(events, summaries).map { event, summary in
            let support = FallbackText.eventSupportText(
                for: summary.category,
                seed: DailyContentSource.eventFingerprint(event),
                isDayPacked: packed
            )
            return DailyContentSource.makeEvent(
                from: event,
                summary: summary.withSupportText(support),
                companionDialogue: FallbackText.taskEncouragement()
            )
        }
        let deadlineTitles = summaries
            .filter { $0.category == .deadline }
            .map(\.title)
        let todayTasks = input.tasks.filter {
            $0.isInTodayDisplay(on: input.now, calendar: input.calendar)
        }
        let completed = todayTasks.count(where: \.isCompleted) + events.count
        let total = todayTasks.count + events.count
        let review = FallbackText.settlementReview(
            deadlineTitles: deadlineTitles,
            focusMinutes: input.focusMinutes,
            tasksCompleted: completed,
            tasksTotal: total
        )
        let quoteBranch = DayPackGenerator.settlementQuoteBranch(
            completed: completed,
            total: total,
            unfinishedEvents: 0,
            combinedMinutes: DayPackGenerator.scheduledEventMinutes(events: events)
                + input.focusMinutes
        )
        let activeCustomCompanion = input.userProfile.customCompanionId.flatMap { id in
            input.customCompanions.first { $0.id == id }
        }
        let quote: String
        switch quoteBranch {
        case .celebration:
            quote = FallbackText.settlementQuoteCelebration(
                style: CompanionTextService.fallbackStyle(for: input.userProfile),
                customVoice: activeCustomCompanion?.personaVoice
            )
        case .overloadedDay:
            quote = FallbackText.settlementQuoteOverloaded(
                style: CompanionTextService.fallbackStyle(for: input.userProfile),
                customVoice: activeCustomCompanion?.personaVoice
            )
        case .fullSchedule:
            quote = FallbackText.settlementQuoteFullSchedule()
        }
        return DailyContentPackage(
            localDate: DailyContentDate(date: input.now, calendar: input.calendar),
            morningDialogue: FallbackText.morningGreeting(for: input.pet.mood),
            idleDialogue: FallbackText.companionPhrase(for: .afternoon),
            closingDialogue: FallbackText.companionPhrase(for: .evening),
            daySummary: FallbackText.daySummary(events: summaries),
            screensaverQuote: ScreensaverService.fallbackQuote,
            screensaverAuthor: input.userProfile.customCompanionId.flatMap { id in
                input.customCompanions.first { $0.id == id }?.name
            } ?? input.userProfile.companionCharacter.displayName,
            settlementReview: review,
            settlementQuote: quote,
            events: dailyEvents
        )
    }
}

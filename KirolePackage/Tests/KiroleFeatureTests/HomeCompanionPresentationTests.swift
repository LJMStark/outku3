import Foundation
import Testing
@testable import KiroleFeature

private actor BlockingSharedDialogueGenerator {
    private var firstCallStarted = false
    private var firstCallStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstCallReleaseContinuation: CheckedContinuation<Void, Never>?
    private var secondCallReleaseContinuation: CheckedContinuation<Void, Never>?
    private var secondCallReleased = false
    private var contexts: [AIContext] = []

    func generate(context: AIContext) async -> String {
        contexts.append(context)
        if contexts.count == 1 {
            firstCallStarted = true
            firstCallStartedContinuation?.resume()
            firstCallStartedContinuation = nil
            await withCheckedContinuation { continuation in
                firstCallReleaseContinuation = continuation
            }
        } else if contexts.count == 2, !secondCallReleased {
            await withCheckedContinuation { continuation in
                secondCallReleaseContinuation = continuation
            }
        }
        return context.topTaskTitles.first == "Revised task"
            ? "The revised task and this line belong together."
            : "This line belongs to the old task."
    }

    func waitUntilFirstCallStarts() async {
        guard !firstCallStarted else { return }
        await withCheckedContinuation { continuation in
            firstCallStartedContinuation = continuation
        }
    }

    func releaseFirstCall() {
        firstCallReleaseContinuation?.resume()
        firstCallReleaseContinuation = nil
    }

    func releaseSecondCall() {
        secondCallReleased = true
        secondCallReleaseContinuation?.resume()
        secondCallReleaseContinuation = nil
    }

    func callCount() -> Int {
        contexts.count
    }
}

@Suite("Home Companion Presentation", .serialized)
struct HomeCompanionPresentationTests {
    @Test("Task change during AI generation publishes only dialogue for final task version")
    @MainActor
    func taskChangeDuringGenerationUsesFinalTaskVersion() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let state = AppState.makeForTesting()
            let storage = LocalStorage.shared
            let generator = BlockingSharedDialogueGenerator()
            let now = Date()

            try await storage.clearAll()
            state.tasks = [TaskItem(id: "task-1", title: "Original task", dueDate: now)]
            state.sharedPetDialogueGenerator = { context, _ in
                await generator.generate(context: context)
            }

            let refresh = Task { @MainActor in
                await state.refreshSharedPetDialogueIfNeeded()
            }
            await generator.waitUntilFirstCallStarts()

            state.tasks = [TaskItem(id: "task-1", title: "Revised task", dueDate: now)]
            let concurrentBLERefresh = Task { @MainActor in
                await state.refreshSharedPetDialogueIfNeeded()
            }
            await generator.releaseFirstCall()

            for _ in 0..<100 {
                if await generator.callCount() == 2 { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            let secondCallStarted = await generator.callCount() == 2
            #expect(secondCallStarted)
            if secondCallStarted {
                #expect(state.currentPetDialogue.isEmpty)
            }

            // Release is sticky: if the expectation above fails, a late second call will not
            // suspend forever and hide the real assertion failure behind a hung test process.
            await generator.releaseSecondCall()
            await refresh.value
            await concurrentBLERefresh.value

            #expect(state.currentPetDialogue == "The revised task and this line belong together.")
            #expect(state.currentPetDialogueTaskStateVersion == state.taskStateVersion)
        }
    }

    @Test("New calendar day resets home companion to daily haiku")
    @MainActor
    func newCalendarDayResetsToDailyHaiku() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let state = AppState.makeForTesting()
            let storage = LocalStorage.shared
            let now = makeDate(year: 2026, month: 4, day: 2, hour: 9)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
            let cachedHaiku = Haiku(lines: [
                "Fresh start arrives",
                "A new page opens quietly",
                "Begin with calm focus"
            ])

            try await storage.clearAll()
            try await storage.cacheHaiku(cachedHaiku, for: now)
            try await storage.saveSharedCompanionDialogue(
                SharedCompanionDialogueCache(
                    date: dateKey(for: now),
                    fingerprint: "today-fingerprint",
                    text: "*waves paw* Today's cached dialogue."
                )
            )
            await storage.saveLastHomeHaikuShownDate(dateKey(for: yesterday))

            state.currentHaiku = .placeholder
            state.currentPetDialogue = ""
            state.homeCompanionDisplayMode = .petDialogue

            await state.refreshHomeCompanionPresentation(now: now)

            #expect(state.homeCompanionDisplayMode == .dailyHaiku)
            #expect(state.currentHaiku.lines == cachedHaiku.lines)
            #expect(state.currentPetDialogue == "*waves paw* Today's cached dialogue.")
            #expect(await storage.loadLastHomeHaikuShownDate() == dateKey(for: now))
        }
    }

    @Test("Same-day revisit stays on pet dialogue and preserves current haiku")
    @MainActor
    func sameDayRevisitStaysOnPetDialogue() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let state = AppState.makeForTesting()
            let storage = LocalStorage.shared
            let now = makeDate(year: 2026, month: 4, day: 2, hour: 14)
            let existingHaiku = Haiku(lines: [
                "Keep this haiku",
                "It should not be replaced today",
                "Dialogue takes over"
            ])

            try await storage.clearAll()
            try await storage.saveSharedCompanionDialogue(
                SharedCompanionDialogueCache(
                    date: dateKey(for: now),
                    fingerprint: "same-day-fingerprint",
                    text: "*leans closer* Same-day cached dialogue."
                )
            )
            await storage.saveLastHomeHaikuShownDate(dateKey(for: now))

            state.currentHaiku = existingHaiku
            state.currentPetDialogue = ""
            state.homeCompanionDisplayMode = .dailyHaiku

            await state.refreshHomeCompanionPresentation(now: now)

            #expect(state.homeCompanionDisplayMode == .petDialogue)
            #expect(state.currentHaiku.lines == existingHaiku.lines)
            #expect(state.currentPetDialogue == "*leans closer* Same-day cached dialogue.")
            #expect(await storage.loadLastHomeHaikuShownDate() == dateKey(for: now))
        }
    }

    @Test("Custom companion fingerprint preserves sub-second updatedAt changes")
    @MainActor
    func customCompanionFingerprintPreservesSubsecondUpdatedAt() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let state = AppState.makeForTesting()
            let storage = LocalStorage.shared
            let now = makeDate(year: 2026, month: 4, day: 2, hour: 15)
            let companionId = UUID()

            try await storage.clearAll()
            let baseUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000.10)
            let baseCompanion = customCompanion(
                id: companionId,
                name: "Mochi",
                updatedAt: baseUpdatedAt
            )
            state.customCompanions = [baseCompanion]
            var profile = state.userProfile
            profile.customCompanionId = companionId
            state.userProfile = profile

            let first = await state.buildCompanionDialogueTriggerState(at: now)

            var editedCompanion = customCompanion(
                id: companionId,
                name: "Mochi II",
                updatedAt: baseUpdatedAt.addingTimeInterval(0.20)
            )
            editedCompanion.relationship = .friend
            state.customCompanions = [editedCompanion]

            let second = await state.buildCompanionDialogueTriggerState(at: now)

            #expect(Int(baseUpdatedAt.timeIntervalSince1970) == Int(editedCompanion.updatedAt.timeIntervalSince1970))
            #expect(first.fingerprint != second.fingerprint)
        }
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        return components.date!
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func customCompanion(id: UUID, name: String, updatedAt: Date) -> CustomCompanion {
        CustomCompanion(
            id: id,
            name: name,
            relationship: .pet,
            personaVoice: .companion,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id),
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}

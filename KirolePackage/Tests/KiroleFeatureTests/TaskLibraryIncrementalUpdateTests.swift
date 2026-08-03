import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task-library stable incremental updates")
struct TaskLibraryIncrementalUpdateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Each content change restarts one three-minute window and only the final source is ready")
    func stabilityWindowRestartsFromLatestChange() {
        let original = [TaskItem(id: "task", title: "First", dueDate: start)]
        var firstEdit = original
        firstEdit[0].title = "Second"
        var finalEdit = firstEdit
        finalEdit[0].notes = "Final notes"
        var state = TaskLibraryStabilityState()

        let recordedFirst = state.recordTaskChanges(from: original, to: firstEdit, at: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar())
        #expect(recordedFirst)
        #expect(state.readyScope(at: start.addingTimeInterval(179)) == nil)
        let recordedFinal = state.recordTaskChanges(
            from: firstEdit,
            to: finalEdit,
            at: start.addingTimeInterval(120),
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar()
        )
        #expect(recordedFinal)
        #expect(state.readyScope(at: start.addingTimeInterval(299)) == nil)
        #expect(state.readyScope(at: start.addingTimeInterval(300)) == .complete)
    }

    @Test("An immediate completion cancels that task's staged copy without delaying another edit")
    func completionDoesNotResetAnotherTasksDeadline() {
        let original = [
            TaskItem(id: "edited", title: "Before", dueDate: start),
            TaskItem(id: "completed", title: "Finish me")
        ]
        var edited = original
        edited[0].title = "After"
        var completed = edited
        completed[1].isCompleted = true
        var state = TaskLibraryStabilityState()

        _ = state.recordTaskChanges(from: original, to: edited, at: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar())
        _ = state.recordTaskChanges(
            from: edited,
            to: completed,
            at: start.addingTimeInterval(60),
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar(),
            immediateRemovalTaskIDs: ["completed"]
        )
        state.promoteImmediateRemoval(taskID: "completed")

        #expect(state.deadline == start.addingTimeInterval(180))
        #expect(state.readyScope(at: start.addingTimeInterval(60)) == .taskRemovals(["completed"]))
        state.markCommitted(
            scope: .taskRemovals(["completed"]),
            capturedGeneration: state.generation
        )
        #expect(state.readyScope(at: start.addingTimeInterval(179)) == nil)
        #expect(state.readyScope(at: start.addingTimeInterval(180)) == .complete)
    }

    @Test("Completing an earlier row does not restart a later task's window")
    func completingEarlierTaskDoesNotChangeRemainingOrder() {
        let original = [
            TaskItem(id: "completed", title: "Finish me"),
            TaskItem(id: "edited", title: "Before", dueDate: start)
        ]
        var edited = original
        edited[1].title = "After"
        var completed = edited
        completed[0].isCompleted = true
        var state = TaskLibraryStabilityState()

        _ = state.recordTaskChanges(from: original, to: edited, at: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar())
        let restarted = state.recordTaskChanges(
            from: edited,
            to: completed,
            at: start.addingTimeInterval(60),
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar(),
            immediateRemovalTaskIDs: ["completed"]
        )
        state.promoteImmediateRemoval(taskID: "completed")

        #expect(!restarted)
        #expect(state.deadline == start.addingTimeInterval(180))
    }

    @MainActor
    @Test("DayPack keeps old task rows until the stability deadline")
    func hardwarePresentationUsesStableTaskProjection() {
        var now = start
        let appState = AppState.makeForTesting()
        appState.taskLibraryNowProvider = { now }
        let original = [TaskItem(id: "task", title: "Before", dueDate: start)]
        appState.tasks = original
        appState.taskLibraryStabilityState = TaskLibraryStabilityState()
        appState.taskLibraryHardwareTasksBaseline = nil
        appState.currentPetDialogue = "Before dialogue"

        var edited = original
        edited[0].title = "After"
        appState.tasks = edited
        appState.currentPetDialogue = "After dialogue"

        #expect(appState.tasksForHardwarePresentation().map(\.title) == ["Before"])
        #expect(appState.petDialogueForHardwarePresentation() == "Before dialogue")
        now = start.addingTimeInterval(180)
        #expect(appState.tasksForHardwarePresentation().map(\.title) == ["After"])
        #expect(appState.petDialogueForHardwarePresentation() == "After dialogue")
    }

    @MainActor
    @Test("A persisted window resumes after restart and becomes ready at its original deadline")
    func persistedWindowRestoresWithoutResettingDeadline() throws {
        let original = [TaskItem(id: "task", title: "Before", dueDate: start)]
        var edited = original
        edited[0].title = "After"
        var restoredState = TaskLibraryStabilityState()
        _ = restoredState.recordTaskChanges(from: original, to: edited, at: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar())
        let appState = AppState.makeForTesting()
        appState.suppressesTaskLibraryChangeTracking = true
        appState.tasks = edited
        appState.suppressesTaskLibraryChangeTracking = false
        var now = start.addingTimeInterval(120)
        appState.taskLibraryNowProvider = { now }
        let checkpoint = TaskLibraryStabilityCheckpoint(
            state: restoredState,
            hardwareTasksBaseline: original,
            hardwarePetDialogueBaseline: "Before dialogue",
            sourceFingerprint: TaskLibrarySourceFingerprint.make(
                tasks: edited,
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions,
                        now: start,
                        calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar()
                    )
        )

        #expect(appState.applyTaskLibraryStabilityCheckpoint(checkpoint))
        #expect(appState.tasksForHardwarePresentation().map(\.title) == ["Before"])
        #expect(appState.taskLibraryReadyUpdate() == nil)
        now = start.addingTimeInterval(180)
        #expect(appState.taskLibraryReadyUpdate()?.scope == .complete)
        #expect(appState.tasksForHardwarePresentation().map(\.title) == ["After"])
        appState.taskLibraryStabilityTask?.cancel()
    }

    @Test("A complete update commits its offline library before the new DayPack")
    func completeUpdateUsesLibraryFirstOrdering() {
        #expect(BLESyncCoordinator.commitsTaskLibraryBeforeDayPack(
            readyUpdate: (.complete, 3)
        ))
        #expect(BLESyncCoordinator.commitsTaskLibraryBeforeDayPack(
            readyUpdate: (.hardwareQueue, 4)
        ))
        #expect(!BLESyncCoordinator.commitsTaskLibraryBeforeDayPack(
            readyUpdate: (.taskRemovals(["done"]), 5)
        ))
        #expect(!BLESyncCoordinator.commitsTaskLibraryBeforeDayPack(readyUpdate: nil))
    }

    @Test("A frozen hardware queue update keeps its projection validation")
    func frozenHardwareQueueKeepsProjectionValidation() {
        let projection = TaskLibraryPendingValidation.hardwareProjection("queue-v2")
        #expect(BLESyncCoordinator.pendingValidationForFrozenUpdate(
            scope: .hardwareQueue,
            plannedValidation: projection
        ) == projection)
        #expect(BLESyncCoordinator.pendingValidationForFrozenUpdate(
            scope: .taskRemovals(["b", "a"]),
            plannedValidation: projection
        ) == .taskRemovals(["a", "b"]))
    }

    @Test("A forced full resync keeps the frozen task source during the stability window")
    func forcedFullResyncUsesFrozenSource() throws {
        let profile = UserProfile.default
        let frozen = TaskItem(id: "task", title: "Before", dueDate: start, notes: "Old notes")
        let phaseTexts = TaskLibraryPhaseTexts(
            starting: "Old start",
            building: "Old middle",
            deep: "Old deep"
        )
        let oldTransaction = try TaskLibraryTransaction.fullLibrary(
            from: [frozen],
            version: TaskLibraryVersion(epoch: 7, revision: 1),
            now: start,
                calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar(),
                phaseTexts: { _ in phaseTexts }
        )
        let baseline = TaskLibraryCommittedSnapshot(
            state: try TaskLibraryCodec.committedState(for: oldTransaction),
            records: oldTransaction.records,
            phaseSourceFingerprints: [
                "task": TaskLibraryPhaseSourceFingerprint.make(
                    task: frozen,
                    userProfile: profile,
                    customCompanions: []
                )
            ],
            personaFingerprint: TaskLibraryPhaseSourceFingerprint.persona(
                userProfile: profile,
                customCompanions: []
            )
        )

        let update = try TaskLibraryUpdatePlanner.makeUpdate(
            tasks: [frozen],
            baseline: baseline,
            version: TaskLibraryVersion(epoch: 7, revision: 2),
            scope: .taskRemovals([]),
            preparedPhaseTexts: [:],
            userProfile: profile,
            customCompanions: [],
            now: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar(),
            forceFullTransaction: true
        )

        #expect(update.transaction.kind == .full)
        #expect(update.targetRecords.map(\.title) == ["Before"])
        #expect(update.targetRecords.first?.phaseTexts == phaseTexts)
    }

    @Test("Undo completion enters the stability window before the task returns")
    func undoCompletionWaitsForCompleteRecord() {
        let completed = [TaskItem(id: "task", title: "Return", isCompleted: true, dueDate: start)]
        let active = [TaskItem(id: "task", title: "Return", isCompleted: false, dueDate: start)]
        var state = TaskLibraryStabilityState()

        let recorded = state.recordTaskChanges(from: completed, to: active, at: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar())
        #expect(recorded)
        #expect(state.readyScope(at: start.addingTimeInterval(179)) == nil)
        #expect(state.readyScope(at: start.addingTimeInterval(180)) == .complete)
    }

    @Test("Date and priority reuse phase copy while title changes prepare only that task")
    func plannerRegeneratesOnlyCopyAffectedByContent() throws {
        let profile = UserProfile.default
        let oldA = TaskItem(
            id: "a",
            title: "Same title",
            dueDate: start,
            priority: .low,
            notes: "Same notes"
        )
        let oldB = TaskItem(id: "b", title: "Old title", dueDate: start, notes: "B notes")
        let oldTextsA = TaskLibraryPhaseTexts(
            starting: "A start",
            building: "A middle",
            deep: "A deep"
        )
        let oldTextsB = TaskLibraryPhaseTexts(
            starting: "B start",
            building: "B middle",
            deep: "B deep"
        )
        let baseTransaction = try TaskLibraryTransaction.fullLibrary(
            from: [oldA, oldB],
            version: TaskLibraryVersion(epoch: 2, revision: 1),
            now: start,
                calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar(),
                phaseTexts: { $0.id == "a" ? oldTextsA : oldTextsB }
        )
        let baseline = TaskLibraryCommittedSnapshot(
            state: try TaskLibraryCodec.committedState(for: baseTransaction),
            records: baseTransaction.records,
            phaseSourceFingerprints: [
                "a": TaskLibraryPhaseSourceFingerprint.make(
                    task: oldA,
                    userProfile: profile,
                    customCompanions: []
                ),
                "b": TaskLibraryPhaseSourceFingerprint.make(
                    task: oldB,
                    userProfile: profile,
                    customCompanions: []
                )
            ]
        )
        var changedA = oldA
        // 同日内改期（+1h）：日期/优先级变化复用旧文案。+86400 会跨日、把任务改出今天集——
        // 那是 deletion 语义，另有专测。
        changedA.dueDate = start.addingTimeInterval(3_600)
        changedA.priority = .high
        var changedB = oldB
        changedB.title = "New title"

        let needing = TaskLibraryUpdatePlanner.tasksNeedingPhaseText(
            tasks: [changedA, changedB],
            baseline: baseline,
            userProfile: profile,
            customCompanions: [],
            now: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar()
        )
        #expect(needing.map(\.id) == ["b"])

        let newTextsB = TaskLibraryPhaseTexts(
            starting: "New B start",
            building: "New B middle",
            deep: "New B deep"
        )
        let update = try TaskLibraryUpdatePlanner.makeUpdate(
            tasks: [changedA, changedB],
            baseline: baseline,
            version: TaskLibraryVersion(epoch: 2, revision: 2),
            scope: .complete,
            preparedPhaseTexts: ["b": newTextsB],
            userProfile: profile,
            customCompanions: [],
            now: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar()
        )

        #expect(update.transaction.kind == .incremental)
        #expect(update.transaction.records.map(\.taskID) == ["a", "b"])
        #expect(update.targetRecords[0].phaseTexts == oldTextsA)
        #expect(update.targetRecords[1].phaseTexts == newTextsB)
        #expect(update.targetRecords[0].dueTimestamp == UInt64(
            changedA.dueDate!.timeIntervalSince1970
        ))
        #expect(update.targetRecords[0].priority == .high)
    }

    @Test("Incremental wire sends only changed and deleted records and commits atomically")
    @MainActor
    func incrementalTransactionAppliesAsOneVersion() async throws {
        let scenario = AppDeviceScenario(now: start)
        scenario.connect()
        let first = try TaskLibraryTransaction.fullLibrary(
            from: [
                TaskItem(id: "a", title: "A", dueDate: start),
                TaskItem(id: "b", title: "B", dueDate: start)
            ],
            version: TaskLibraryVersion(epoch: 3, revision: 1),
            now: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar()
        )
        let firstAck = try scenario.sendTaskLibrary(first, messageID: 0x7000, maxChunkSize: 32)
        var changedA = first.records[0]
        changedA = TaskLibraryRecord(
            taskID: changedA.taskID,
            order: 0,
            title: "A changed",
            detail: changedA.detail,
            dueTimestamp: changedA.dueTimestamp,
            priority: .high,
            phaseTexts: changedA.phaseTexts
        )
        let delta = TaskLibraryTransaction.incremental(
            from: TaskLibraryCommittedState(
                version: firstAck.version,
                contentCRC32: firstAck.contentCRC32
            ),
            to: TaskLibraryVersion(epoch: 3, revision: 2),
            upserts: [changedA],
            deletions: ["b"]
        )

        let decoded = try TaskLibraryCodec.decodeTransaction(
            TaskLibraryCodec.encodeTransaction(delta)
        )
        #expect(decoded == delta)
        #expect(decoded.records.map(\.taskID) == ["a"])
        #expect(decoded.deletedTaskIDs == ["b"])

        let acknowledgement = try scenario.sendTaskLibrary(
            delta,
            messageID: 0x7001,
            maxChunkSize: 24
        )
        let snapshot = await scenario.snapshot()
        #expect(acknowledgement.result == .committed)
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["a"])
        #expect(snapshot.taskLibraryRecords.first?.title == "A changed")
    }

    @Test("A delta with the wrong base leaves the previous library untouched")
    @MainActor
    func baseMismatchPreservesCommittedLibrary() async throws {
        let scenario = AppDeviceScenario(now: start)
        scenario.connect()
        let first = try TaskLibraryTransaction.fullLibrary(
            from: [TaskItem(id: "a", title: "A", dueDate: start)],
            version: TaskLibraryVersion(epoch: 4, revision: 1),
            now: start,
            calendar: TaskLibraryFullSyncTests.makeShanghaiCalendar()
        )
        _ = try scenario.sendTaskLibrary(first, messageID: 0x7100, maxChunkSize: 32)
        let wrongBase = TaskLibraryCommittedState(
            version: TaskLibraryVersion(epoch: 99, revision: 1),
            contentCRC32: 0x1234_5678
        )
        let delta = TaskLibraryTransaction.incremental(
            from: wrongBase,
            to: TaskLibraryVersion(epoch: 4, revision: 2),
            upserts: [],
            deletions: ["a"]
        )

        let acknowledgement = try scenario.sendTaskLibrary(
            delta,
            messageID: 0x7101,
            maxChunkSize: 32
        )
        let snapshot = await scenario.snapshot()
        #expect(acknowledgement.result == .baseMismatch)
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["a"])
        #expect(snapshot.taskLibraryCommittedVersion == first.version)
    }

    // MARK: - Today-only membership (2026-08-04)

    @Test("A task leaving today becomes an incremental deletion and a manual selection an upsert")
    func todayMembershipDrivesUpsertsAndDeletions() throws {
        let calendar = TaskLibraryFullSyncTests.makeShanghaiCalendar()
        let profile = UserProfile.default
        let dueToday = TaskItem(id: "stay", title: "Stays today", dueDate: start)
        let leaving = TaskItem(id: "leave", title: "Leaves today", dueDate: start)
        let manual = TaskItem(id: "manual", title: "Joins today", todayDisplayDate: start)

        let base = try TaskLibraryTransaction.fullLibrary(
            from: [dueToday, leaving],
            version: TaskLibraryVersion(epoch: 20, revision: 1),
            now: start,
            calendar: calendar,
            // 与 planner 的按角色 fallback 一致，否则未变更的 record 会被误判为 upsert。
            phaseTexts: { _ in .localFallback(for: profile.companionCharacter) }
        )
        let baseline = TaskLibraryCommittedSnapshot(
            state: try TaskLibraryCodec.committedState(for: base),
            records: base.records,
            phaseSourceFingerprints: [:],
            personaFingerprint: TaskLibraryPhaseSourceFingerprint.persona(
                userProfile: profile,
                customCompanions: []
            )
        )

        // 用户把 leave 的日期改到明天（掉出今天），并把无日期任务手动设为今天。
        var movedOut = leaving
        movedOut.dueDate = start.addingTimeInterval(24 * 60 * 60)

        let update = try TaskLibraryUpdatePlanner.makeUpdate(
            tasks: [dueToday, movedOut, manual],
            baseline: baseline,
            version: TaskLibraryVersion(epoch: 20, revision: 2),
            scope: .complete,
            preparedPhaseTexts: [:],
            userProfile: profile,
            customCompanions: [],
            now: start,
            calendar: calendar
        )

        #expect(update.transaction.kind == .incremental)
        #expect(update.transaction.deletedTaskIDs == ["leave"])
        #expect(update.transaction.records.map(\.taskID) == ["manual"])
        #expect(update.targetRecords.map(\.taskID) == ["stay", "manual"])
    }

    @Test("Setting a task to today opens one stability window and is ready only at 180 seconds")
    func manualTodaySelectionUsesTheStabilityWindow() {
        let calendar = TaskLibraryFullSyncTests.makeShanghaiCalendar()
        var state = TaskLibraryStabilityState()
        let undated = TaskItem(id: "manual", title: "Pick me")
        var selected = undated
        selected.todayDisplayDate = start

        // 手动设为今天：进集合 = 变化，开 180 秒窗（客户拍板：走三分钟推送规则）。
        let selectionRecorded = state.recordTaskChanges(
            from: [undated],
            to: [selected],
            at: start,
            calendar: calendar
        )
        #expect(selectionRecorded)
        #expect(state.readyScope(at: start.addingTimeInterval(179)) == nil)
        #expect(state.readyScope(at: start.addingTimeInterval(180)) == .complete)

        // 移出今天：出集合 = 变化，同样走窗。
        var afterCommit = TaskLibraryStabilityState()
        let removalRecorded = afterCommit.recordTaskChanges(
            from: [selected],
            to: [undated],
            at: start,
            calendar: calendar
        )
        #expect(removalRecorded)
        #expect(afterCommit.readyScope(at: start.addingTimeInterval(180)) == .complete)
    }

    @Test("Yesterday's frozen pending source cannot validate on the new local day")
    @MainActor
    func pendingValidationIsDayBound() {
        let calendar = TaskLibraryFullSyncTests.makeShanghaiCalendar()
        let appState = AppState.shared
        let previousTasks = appState.tasks
        let previousNow = appState.taskLibraryNowProvider
        let previousCalendar = appState.dailyContentCalendarProvider
        defer {
            appState.tasks = previousTasks
            appState.taskLibraryNowProvider = previousNow
            appState.dailyContentCalendarProvider = previousCalendar
        }

        let task = TaskItem(id: "day-bound", title: "Day bound", dueDate: start)
        appState.tasks = [task]
        appState.dailyContentCalendarProvider = { calendar }
        appState.taskLibraryNowProvider = { self.start }

        let frozenYesterday = TaskLibraryPendingValidation.completeSource(
            TaskLibrarySourceFingerprint.make(
                tasks: [task],
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions,
                now: start,
                calendar: calendar
            )
        )
        #expect(frozenYesterday.matchesCurrentSource())

        // 跨到明天：同一份任务数组，指纹因本地日与成员资格变化而失配。
        appState.taskLibraryNowProvider = { self.start.addingTimeInterval(24 * 60 * 60) }
        #expect(!frozenYesterday.matchesCurrentSource())
    }

    @Test("A removal pending is satisfied when its task left today and blocked when it joined")
    @MainActor
    func removalValidationTracksTodayMembership() {
        let calendar = TaskLibraryFullSyncTests.makeShanghaiCalendar()
        let appState = AppState.shared
        let previousTasks = appState.tasks
        let previousNow = appState.taskLibraryNowProvider
        let previousCalendar = appState.dailyContentCalendarProvider
        defer {
            appState.tasks = previousTasks
            appState.taskLibraryNowProvider = previousNow
            appState.dailyContentCalendarProvider = previousCalendar
        }
        appState.dailyContentCalendarProvider = { calendar }
        appState.taskLibraryNowProvider = { self.start }

        let tomorrow = start.addingTimeInterval(24 * 60 * 60)
        // 任务已不在今天集（改期到明天）：旧 removal 判满足——设备上本就不该再有它。
        appState.tasks = [TaskItem(id: "moved", title: "Moved", dueDate: tomorrow)]
        let removal = TaskLibraryPendingValidation.taskRemovals(
            [TaskItem(id: "moved", title: "Moved", dueDate: tomorrow).hardwareIdentifier]
        )
        #expect(removal.matchesCurrentSource())

        // 同一任务回到今天集：removal 不再满足。
        appState.tasks = [TaskItem(id: "moved", title: "Moved", dueDate: start)]
        #expect(!removal.matchesCurrentSource())
    }
}

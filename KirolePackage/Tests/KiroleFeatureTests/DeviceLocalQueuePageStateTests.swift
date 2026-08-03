import Foundation
import Testing
@testable import KiroleFeature

@Suite("Device local queue and page state", .serialized)
@MainActor
struct DeviceLocalQueuePageStateTests {
    @Test("An empty committed queue has no selectable task")
    func emptyQueueCannotEnterFocus() async throws {
        let scenario = AppDeviceScenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        scenario.connect()
        _ = try scenario.sendTaskLibrary(
            TaskLibraryTransaction(
                version: TaskLibraryVersion(epoch: 22, revision: 2),
                records: []
            ),
            messageID: 0x7221,
            maxChunkSize: 24
        )

        #expect(throws: SimulationError.taskLibraryTaskNotFound) {
            _ = try scenario.shortPressOverview()
        }
        let snapshot = await scenario.snapshot()
        #expect(snapshot.currentPage == .overview)
        #expect(snapshot.deviceFocus == nil)
        #expect(snapshot.staticFeedback == .none)
    }

    @Test("Overview short press can only enter the committed queue head and reads all copy locally")
    func overviewShortPressUsesCommittedQueueHeadWithoutTaskIn() async throws {
        let scenario = try makeScenario()

        #expect(throws: SimulationError.taskLibraryTaskNotFound) {
            _ = try scenario.enterTaskFromCommittedLibrary(taskID: "second")
        }

        let entered = try scenario.shortPressOverview()
        let snapshot = await scenario.snapshot()

        #expect(entered.taskID == "first")
        #expect(entered.detail == "First detail")
        #expect(snapshot.currentPage == .focus(taskID: "first"))
        #expect(snapshot.deviceFocus?.taskID == "first")
        #expect(try scenario.currentTaskPhaseText(elapsedMinutes: 0) == "First 0-5")
        #expect(try scenario.currentTaskPhaseText(elapsedMinutes: 5) == "First 0-5")
        #expect(try scenario.currentTaskPhaseText(elapsedMinutes: 6) == "First 6-15")
        #expect(try scenario.currentTaskPhaseText(elapsedMinutes: 15) == "First 6-15")
        #expect(try scenario.currentTaskPhaseText(elapsedMinutes: 16) == "First 16+")
        #expect(!snapshot.outboundTransactions.contains {
            $0.type == BLEDataType.taskInPage.rawValue
        })
    }

    @Test("Completing the queue head removes it, promotes the next task, and restores the focus source page")
    func completeRemovesHeadAndRestoresSource() async throws {
        let scenario = try makeScenario()
        scenario.showDevicePage(.dailySummary)
        _ = try scenario.enterTaskFromQueueHead()

        let completed = try scenario.completeCurrentTaskLocally()
        let snapshot = await scenario.snapshot()

        #expect(completed.taskID == "first")
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["second"])
        #expect(snapshot.taskLibraryRecords.map(\.order) == [0])
        #expect(snapshot.deviceCompletedTaskIDs == ["first"])
        #expect(snapshot.currentPage == .dailySummary)
        #expect(snapshot.deviceFocus == nil)
        #expect(snapshot.staticFeedback == .none)

        scenario.showDevicePage(.overview)
        #expect(try scenario.shortPressOverview().taskID == "second")
    }

    @Test("Skipping keeps the task incomplete, rotates it to the tail, and restores the focus source page")
    func skipRotatesHeadWithoutRewardOrFeedback() async throws {
        let scenario = try makeScenario()
        scenario.showDevicePage(.screensaver)
        _ = try scenario.enterTaskFromQueueHead()

        let skipped = try scenario.skipCurrentTaskLocally()
        let snapshot = await scenario.snapshot()

        #expect(skipped.taskID == "first")
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["second", "first"])
        #expect(snapshot.taskLibraryRecords.map(\.order) == [0, 1])
        #expect(snapshot.deviceCompletedTaskIDs.isEmpty)
        #expect(snapshot.deviceRewardCount == 0)
        #expect(snapshot.currentPage == .screensaver)
        #expect(snapshot.deviceFocus == nil)
        #expect(snapshot.staticFeedback == .none)
    }

    @Test("Daily summary and screensaver each restore the page that opened them")
    func transientPagesRestoreTheirOwnSource() async throws {
        let scenario = try makeScenario()

        scenario.showDevicePage(.overview)
        scenario.showDailySummary()
        #expect(await scenario.snapshot().currentPage == .dailySummary)
        try scenario.longPressDailySummary()
        #expect(await scenario.snapshot().currentPage == .overview)

        scenario.showDevicePage(.dailySummary)
        scenario.enterScreensaver()
        #expect(await scenario.snapshot().currentPage == .screensaver)
        try scenario.exitScreensaver()
        let snapshot = await scenario.snapshot()
        #expect(snapshot.currentPage == .dailySummary)
        #expect(snapshot.staticFeedback == .none)
    }

    private func makeScenario() throws -> AppDeviceScenario {
        let scenario = AppDeviceScenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        scenario.connect()
        _ = try scenario.sendTaskLibrary(
            TaskLibraryTransaction(
                version: TaskLibraryVersion(epoch: 22, revision: 1),
                records: [
                    makeRecord(
                        id: "first",
                        order: 0,
                        title: "First task",
                        detail: "First detail"
                    ),
                    makeRecord(
                        id: "second",
                        order: 1,
                        title: "Second task",
                        detail: "Second detail"
                    ),
                ]
            ),
            messageID: 0x7220,
            maxChunkSize: 24
        )
        return scenario
    }

    private func makeRecord(
        id: String,
        order: UInt32,
        title: String,
        detail: String
    ) -> TaskLibraryRecord {
        TaskLibraryRecord(
            taskID: id,
            order: order,
            title: title,
            detail: detail,
            phaseTexts: TaskLibraryPhaseTexts(
                starting: "\(title.split(separator: " ")[0]) 0-5",
                building: "\(title.split(separator: " ")[0]) 6-15",
                deep: "\(title.split(separator: " ")[0]) 16+"
            )
        )
    }
}

import Foundation
import Testing
@testable import KiroleFeature

@Suite("FocusContinuityScenarioTests", .serialized)
@MainActor
struct FocusContinuityScenarioTests {
    @Test("Disconnect keeps the same local focus across every phase boundary and reconnect")
    func disconnectKeepsLocalFocusClockContinuous() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let record = Self.record(
            title: "Original title",
            prefix: "original"
        )

        scenario.connect()
        _ = try scenario.sendTaskLibrary(
            TaskLibraryTransaction(
                version: TaskLibraryVersion(epoch: 1, revision: 1),
                records: [record]
            ),
            messageID: 0x7301,
            maxChunkSize: 24
        )
        _ = try scenario.enterTaskFromQueueHead()
        let startedAt = try #require((await scenario.snapshot()).deviceFocus?.startedAt)

        scenario.disconnect()
        #expect(try scenario.currentTaskPhaseText() == "original 0-5")

        await scenario.advance(by: .seconds(5 * 60))
        #expect(try scenario.currentTaskPhaseText() == "original 0-5")

        await scenario.advance(by: .seconds(60))
        #expect(try scenario.currentTaskPhaseText() == "original 6-15")

        await scenario.advance(by: .seconds(9 * 60))
        #expect(try scenario.currentTaskPhaseText() == "original 6-15")

        await scenario.advance(by: .seconds(60))
        #expect(try scenario.currentTaskPhaseText() == "original 16+")

        try scenario.reconnectFocus(taskID: record.taskID, elapsedMinutes: 16)

        let snapshot = await scenario.snapshot()
        #expect(snapshot.connectionState == .connected)
        #expect(snapshot.currentPage == .focus(taskID: record.taskID))
        #expect(snapshot.deviceFocus?.taskID == record.taskID)
        #expect(snapshot.deviceFocus?.startedAt == startedAt)
        #expect(try scenario.currentTaskPhaseText() == "original 16+")
    }

    @Test("A library update cannot replace visible focus copy until the next entry")
    func activeFocusFreezesTaskCopyAcrossReconnect() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let original = Self.record(title: "Original title", prefix: "original")
        let updated = Self.record(title: "Updated title", prefix: "updated")

        scenario.connect()
        _ = try scenario.sendTaskLibrary(
            TaskLibraryTransaction(
                version: TaskLibraryVersion(epoch: 1, revision: 1),
                records: [original]
            ),
            messageID: 0x7311,
            maxChunkSize: 24
        )
        _ = try scenario.enterTaskFromQueueHead()
        let startedAt = try #require((await scenario.snapshot()).deviceFocus?.startedAt)

        scenario.disconnect()
        await scenario.advance(by: .seconds(3 * 60))
        try scenario.reconnectFocus(taskID: original.taskID, elapsedMinutes: 3)
        _ = try scenario.sendTaskLibrary(
            TaskLibraryTransaction(
                version: TaskLibraryVersion(epoch: 1, revision: 2),
                records: [updated]
            ),
            messageID: 0x7312,
            maxChunkSize: 24
        )

        var snapshot = await scenario.snapshot()
        #expect(snapshot.taskLibraryRecords.first?.title == "Updated title")
        #expect(snapshot.deviceFocus?.task.title == "Original title")
        #expect(snapshot.deviceFocus?.startedAt == startedAt)
        #expect(try scenario.currentTaskPhaseText() == "original 0-5")

        _ = try scenario.skipCurrentTaskLocally()
        _ = try scenario.enterTaskFromQueueHead()

        snapshot = await scenario.snapshot()
        #expect(snapshot.deviceFocus?.task.title == "Updated title")
        #expect(try scenario.currentTaskPhaseText() == "updated 0-5")
    }

    private static let startDate = Date(timeIntervalSince1970: 1_778_100_000)

    private static func record(title: String, prefix: String) -> TaskLibraryRecord {
        TaskLibraryRecord(
            taskID: "focus-task",
            order: 0,
            title: title,
            detail: "\(title) detail",
            phaseTexts: TaskLibraryPhaseTexts(
                starting: "\(prefix) 0-5",
                building: "\(prefix) 6-15",
                deep: "\(prefix) 16+"
            )
        )
    }
}

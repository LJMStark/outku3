import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLE DeviceWake sync deduplication")
struct BLEDeviceWakeSyncDeduplicationTests {
    @Test("A DeviceWake merged into a successful routine sync launches one transaction")
    func activeRoutineSyncConsumesWakeAfterSuccess() throws {
        let fixture = try Self.loadFixture()
        var state = BLEDeviceWakeSyncState()
        var launchedTransactions = 0

        let started = state.beginSync(
            force: false,
            hardwareWakeDate: nil,
            taskActionBlocked: false
        )
        #expect(started)
        launchedTransactions += 1
        let wakeDecision = state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: false
        )
        #expect(wakeDecision == .mergeIntoActiveSync)
        state.closeDeviceWakeMergeWindow()
        state.finishActiveSync(transactionCommitted: true)
        let unexpectedRetry = state.reservePendingSyncIfPossible(taskActionBlocked: false)
        if unexpectedRetry != nil {
            launchedTransactions += 1
        }

        #expect(fixture.hasObservedCollisionTimeline)
        #expect(fixture.observedOfflineSyncTransactionCount == 2)
        #expect(launchedTransactions == 1)
        #expect(!state.isSyncing)
        #expect(state.pendingRequest == nil)
    }

    @Test("A DeviceWake merged into a failed routine sync launches exactly one forced retry")
    func failedRoutineSyncRetainsOneForcedWakeRetry() throws {
        let fixture = try Self.loadFixture()
        var state = BLEDeviceWakeSyncState()
        var launchedTransactions = 0

        let started = state.beginSync(
            force: false,
            hardwareWakeDate: nil,
            taskActionBlocked: false
        )
        #expect(started)
        launchedTransactions += 1
        let wakeDecision = state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: false
        )
        #expect(wakeDecision == .mergeIntoActiveSync)
        state.closeDeviceWakeMergeWindow()
        state.finishActiveSync(transactionCommitted: false)

        let pendingRetry = state.reservePendingSyncIfPossible(taskActionBlocked: false)
        let retry = try #require(pendingRetry)
        launchedTransactions += 1
        #expect(retry.force)
        #expect(retry.hardwareWakeDate == fixture.deviceWakeDate)
        state.closeDeviceWakeMergeWindow()
        state.finishActiveSync(transactionCommitted: true)

        #expect(launchedTransactions == 2)
        #expect(state.pendingRequest == nil)
    }

    @Test("Task action presentation queues DeviceWake until its boundary is released")
    func taskActionPresentationQueuesWakeWithoutActiveSync() throws {
        let fixture = try Self.loadFixture()
        var state = BLEDeviceWakeSyncState()

        let wakeDecision = state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: true
        )
        #expect(wakeDecision == .enqueueForcedSync)
        let blockedReservation = state.reservePendingSyncIfPossible(taskActionBlocked: true)
        #expect(blockedReservation == nil)
        let pendingRequest = state.reservePendingSyncIfPossible(taskActionBlocked: false)
        let request = try #require(pendingRequest)

        #expect(request.force)
        #expect(request.hardwareWakeDate == fixture.deviceWakeDate)
        #expect(state.isSyncing)
    }

    @Test("A frozen active sync queues DeviceWake for a later transaction")
    func nonAbsorbingActiveSyncQueuesForcedWake() throws {
        let fixture = try Self.loadFixture()
        var state = BLEDeviceWakeSyncState()

        let started = state.beginSync(
            force: false,
            hardwareWakeDate: nil,
            taskActionBlocked: false
        )
        #expect(started)
        state.closeDeviceWakeMergeWindow()
        let wakeDecision = state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: false
        )
        #expect(wakeDecision == .enqueueForcedSync)
        state.finishActiveSync(transactionCommitted: true)
        let pendingRequest = state.reservePendingSyncIfPossible(taskActionBlocked: false)
        let request = try #require(pendingRequest)

        #expect(request.force)
        #expect(request.hardwareWakeDate == fixture.deviceWakeDate)
    }

    @Test("A DeviceWake arriving during cancellation cleanup survives the cancelled sync")
    func cancellationCleanupQueuesLateWake() throws {
        let fixture = try Self.loadFixture()
        var state = BLEDeviceWakeSyncState()

        let started = state.beginSync(
            force: false,
            hardwareWakeDate: nil,
            taskActionBlocked: false
        )
        #expect(started)

        // Cancellation closes the merge window before its first await. A DeviceWake delivered
        // during the await must become a pending forced sync, not merge into the cancelled run.
        state.closeDeviceWakeMergeWindow()
        #expect(!state.activeSyncHadMergedWake)
        #expect(state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: false
        ) == .enqueueForcedSync)

        state.finishActiveSync(
            transactionCommitted: false,
            retryMergedWake: false
        )
        let pendingRequest = state.reservePendingSyncIfPossible(taskActionBlocked: false)
        let request = try #require(pendingRequest)
        #expect(request.force)
        #expect(request.hardwareWakeDate == fixture.deviceWakeDate)
    }

    @Test("DeviceWake reserves a dedicated active sync while the coordinator is idle")
    func idleCoordinatorStartsDedicatedWakeSync() throws {
        let fixture = try Self.loadFixture()
        var state = BLEDeviceWakeSyncState()

        let wakeDecision = state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: false
        )
        #expect(wakeDecision == .startDedicatedSync)
        #expect(state.isSyncing)
        #expect(state.activeHardwareWakeDate == fixture.deviceWakeDate)
    }

    @Test("A deterministic INVALID_STATE failure does not enqueue a merged DeviceWake retry")
    func deterministicRejectionDoesNotEnqueueMergedWakeRetry() throws {
        let fixture = try Self.loadFixture()
        var state = BLEDeviceWakeSyncState()

        let started = state.beginSync(
            force: false,
            hardwareWakeDate: nil,
            taskActionBlocked: false
        )
        #expect(started)
        let wakeDecision = state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: false
        )
        #expect(wakeDecision == .mergeIntoActiveSync)
        state.closeDeviceWakeMergeWindow()
        state.finishActiveSync(transactionCommitted: false, retryMergedWake: false)

        #expect(state.pendingRequest == nil)
        #expect(!state.isSyncing)
    }

    @Test("An unrelated failed sync does not invent a DeviceWake retry")
    func failedSyncWithoutMergedWakeDoesNotRetryWake() {
        var state = BLEDeviceWakeSyncState()

        let started = state.beginSync(
            force: false,
            hardwareWakeDate: nil,
            taskActionBlocked: false
        )
        #expect(started)
        state.closeDeviceWakeMergeWindow()
        state.finishActiveSync(transactionCommitted: false)

        #expect(state.pendingRequest == nil)
    }

    @Test("Multiple DeviceWake events coalesce into one request with the latest timestamp")
    func multipleQueuedWakesCoalesce() throws {
        let fixture = try Self.loadFixture()
        let laterWake = fixture.deviceWakeDate.addingTimeInterval(5)
        var state = BLEDeviceWakeSyncState()

        let started = state.beginSync(
            force: false,
            hardwareWakeDate: nil,
            taskActionBlocked: false
        )
        #expect(started)
        state.closeDeviceWakeMergeWindow()
        let firstDecision = state.handleDeviceWake(
            at: fixture.deviceWakeDate,
            taskActionBlocked: false
        )
        let secondDecision = state.handleDeviceWake(at: laterWake, taskActionBlocked: false)
        #expect(firstDecision == .enqueueForcedSync)
        #expect(secondDecision == .enqueueForcedSync)
        state.finishActiveSync(transactionCommitted: true)
        let pendingRequest = state.reservePendingSyncIfPossible(taskActionBlocked: false)
        let request = try #require(pendingRequest)

        #expect(request.force)
        #expect(request.hardwareWakeDate == laterWake)
        #expect(state.pendingRequest == nil)
    }

    @Test("Taking a pending retry reserves its slot before the launch Task runs")
    func scheduledRetryHasNoIdleSchedulingGap() throws {
        let fixture = try Self.loadFixture()
        let wakeDuringSchedulingGap = fixture.deviceWakeDate.addingTimeInterval(1)
        var state = BLEDeviceWakeSyncState()

        state.enqueue(force: true, hardwareWakeDate: fixture.deviceWakeDate)
        let pendingRequest = state.reservePendingSyncIfPossible(taskActionBlocked: false)
        let scheduled = try #require(pendingRequest)

        #expect(scheduled.force)
        #expect(state.isSyncing)
        let wakeDecision = state.handleDeviceWake(
            at: wakeDuringSchedulingGap,
            taskActionBlocked: false
        )
        #expect(wakeDecision == .mergeIntoActiveSync)
        #expect(state.pendingRequest == nil)
        #expect(state.activeHardwareWakeDate == wakeDuringSchedulingGap)
    }

    private static func loadFixture() throws -> DeviceWakeSyncFixture {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent(
                "test/fixtures/ios-fix/ble-device-wake-during-routine-sync.json"
            )
        return try JSONDecoder().decode(
            DeviceWakeSyncFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
    }
}

private struct DeviceWakeSyncFixture: Decodable {
    let connectedAtMilliseconds: Int
    let deviceWakeAtMilliseconds: Int
    let firstTimeFrameAtMilliseconds: Int
    let firstCommitAtMilliseconds: Int
    let secondTimeFrameAtMilliseconds: Int
    let observedOfflineSyncTransactionCount: Int

    var deviceWakeDate: Date {
        Date(timeIntervalSince1970: Double(deviceWakeAtMilliseconds) / 1_000)
    }

    var hasObservedCollisionTimeline: Bool {
        connectedAtMilliseconds < deviceWakeAtMilliseconds
            && deviceWakeAtMilliseconds < firstTimeFrameAtMilliseconds
            && firstTimeFrameAtMilliseconds < firstCommitAtMilliseconds
            && firstCommitAtMilliseconds < secondTimeFrameAtMilliseconds
    }
}

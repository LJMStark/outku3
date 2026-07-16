import Testing
import Foundation
@testable import KiroleFeature

@Suite("BLEEventHandlerTests")
struct BLEEventHandlerTests {

    // MARK: - filterAndSortForMutation

    @Test("given events older than or equal to lastTimestamp, when filtered, then they are dropped")
    func givenOldEvents_whenFiltered_thenDropped() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "a", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "b", timestamp: Date(timeIntervalSince1970: 200)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 100)

        #expect(result.count == 1)
        #expect(result[0].taskId == "b")
    }

    @Test("given lastTimestamp is zero, when filtered, then all events are returned")
    func givenZeroLastTimestamp_whenFiltered_thenAllReturned() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "x", timestamp: Date(timeIntervalSince1970: 1)),
            EventLog(eventType: .completeTask, taskId: "y", timestamp: Date(timeIntervalSince1970: 2)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 2)
    }

    @Test("given out-of-order events, when sorted, then timestamps are ascending")
    func givenOutOfOrderEvents_whenSorted_thenAscendingTimestamps() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "late",  timestamp: Date(timeIntervalSince1970: 300)),
            EventLog(eventType: .completeTask, taskId: "early", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "mid",   timestamp: Date(timeIntervalSince1970: 200)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.map(\.taskId) == ["early", "mid", "late"])
    }

    @Test("given duplicate events with identical content triplet, when deduplicated, then only one is kept")
    func givenDuplicateContentTriplet_whenDeduplicated_thenOnlyOneKept() {
        let ts = Date(timeIntervalSince1970: 500)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "dup", timestamp: ts),
            EventLog(eventType: .completeTask, taskId: "dup", timestamp: ts),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 1)
    }

    @Test("given same eventType and timestamp but different taskIds, when deduplicated, then both are kept")
    func givenSameTypeAndTimestampDifferentTaskIds_whenDeduplicated_thenBothKept() {
        let ts = Date(timeIntervalSince1970: 500)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "task-1", timestamp: ts),
            EventLog(eventType: .completeTask, taskId: "task-2", timestamp: ts),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 2)
    }

    @Test("given same taskId completed at different times, when deduplicated, then both are kept")
    func givenSameTaskIdDifferentTimestamps_whenDeduplicated_thenBothKept() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "t", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "t", timestamp: Date(timeIntervalSince1970: 200)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 2)
    }

    // MARK: - eventContentKey

    @Test("given two EventLogs with identical content but different UUIDs, when keyed, then keys are equal")
    func givenSameContentDifferentUUID_whenKeyed_thenKeysEqual() {
        let ts = Date(timeIntervalSince1970: 999)
        let log1 = EventLog(eventType: .completeTask, taskId: "abc", timestamp: ts)
        let log2 = EventLog(eventType: .completeTask, taskId: "abc", timestamp: ts)

        #expect(log1.id != log2.id)
        #expect(BLEEventHandler.eventContentKey(log1) == BLEEventHandler.eventContentKey(log2))
    }

    // MARK: - hasDeviceTimestamp parsing (A1)

    private func taskPayload(taskId: String, deviceTimestamp ts: UInt32?) -> Data {
        var data = Data([UInt8(taskId.utf8.count)])
        data.append(contentsOf: Array(taskId.utf8))
        if let ts {
            data.append(contentsOf: [
                UInt8((ts >> 24) & 0xFF), UInt8((ts >> 16) & 0xFF),
                UInt8((ts >> 8) & 0xFF), UInt8(ts & 0xFF),
            ])
        }
        return data
    }

    @Test("given completeTask payload with 4-byte device timestamp, when parsed, then hasDeviceTimestamp is true")
    func givenCompleteTaskWithDeviceTimestamp_whenParsed_thenHasDeviceTimestampTrue() {
        let payload = taskPayload(taskId: "t1", deviceTimestamp: 1_700_000_000)
        let log = EventLog.fromBLEPayload(type: EventLogType.completeTask.rawByte, payload: payload)
        #expect(log?.hasDeviceTimestamp == true)
        #expect(log?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("given completeTask payload without timestamp bytes, when parsed, then hasDeviceTimestamp is false")
    func givenCompleteTaskWithoutTimestamp_whenParsed_thenHasDeviceTimestampFalse() {
        let payload = taskPayload(taskId: "t1", deviceTimestamp: nil)
        let log = EventLog.fromBLEPayload(type: EventLogType.completeTask.rawByte, payload: payload)
        #expect(log?.hasDeviceTimestamp == false)
    }

    @Test("given a deviceWake event, when parsed, then it never carries a device timestamp")
    func givenDeviceWake_whenParsed_thenHasDeviceTimestampFalse() {
        let log = EventLog.fromBLEPayload(type: EventLogType.deviceWake.rawByte, payload: Data([80]))
        #expect(log?.eventType == .deviceWake)
        #expect(log?.hasDeviceTimestamp == false)
    }

    @Test("given reminderAcknowledged with 4-byte timestamp, when parsed, then hasDeviceTimestamp is true")
    func givenReminderAckWithTimestamp_whenParsed_thenHasDeviceTimestampTrue() {
        let ts: UInt32 = 1_700_000_500
        let payload = Data([
            UInt8((ts >> 24) & 0xFF), UInt8((ts >> 16) & 0xFF),
            UInt8((ts >> 8) & 0xFF), UInt8(ts & 0xFF),
        ])
        let log = EventLog.fromBLEPayload(type: EventLogType.reminderAcknowledged.rawByte, payload: payload)
        #expect(log?.hasDeviceTimestamp == true)
    }

    // MARK: - nextEventLogWatermark (A1/A4)

    @Test("given a deviceWake fallback plus an earlier real completion, when computing watermark, then only the device-timestamped event advances it")
    func givenFallbackPlusRealEvent_whenWatermark_thenOnlyDeviceTimestampAdvances() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = [
            // Reconnect order: deviceWake stamped "now" by the App, but no device clock.
            EventLog(eventType: .deviceWake, timestamp: now, hasDeviceTimestamp: false),
            // The offline completion the user actually made, on an earlier device clock.
            EventLog(eventType: .completeTask, taskId: "a",
                     timestamp: Date(timeIntervalSince1970: 1_699_000_000), hasDeviceTimestamp: true),
        ]
        let watermark = BLEEventHandler.nextEventLogWatermark(current: 0, logs: logs, now: now)
        #expect(watermark == 1_699_000_000)
    }

    @Test("given a batch of only fallback events, when computing watermark, then it returns nil (no advance)")
    func givenOnlyFallbackEvents_whenWatermark_thenNil() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = [
            EventLog(eventType: .deviceWake, timestamp: now, hasDeviceTimestamp: false),
            EventLog(eventType: .requestRefresh, timestamp: now, hasDeviceTimestamp: false),
        ]
        #expect(BLEEventHandler.nextEventLogWatermark(current: 0, logs: logs, now: now) == nil)
    }

    @Test("given a future-skewed device timestamp beyond now+48h, when computing watermark, then it is ignored (A4)")
    func givenFutureSkewedTimestamp_whenWatermark_thenIgnored() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let poison = UInt32(now.timeIntervalSince1970) + (72 * 60 * 60) // 72h in the future
        let good: UInt32 = 1_699_500_000
        let logs = [
            EventLog(eventType: .completeTask, taskId: "poison",
                     timestamp: Date(timeIntervalSince1970: TimeInterval(poison)), hasDeviceTimestamp: true),
            EventLog(eventType: .completeTask, taskId: "good",
                     timestamp: Date(timeIntervalSince1970: TimeInterval(good)), hasDeviceTimestamp: true),
        ]
        #expect(BLEEventHandler.nextEventLogWatermark(current: 0, logs: logs, now: now) == good)
    }

    @Test("given a device timestamp not greater than current, when computing watermark, then it returns nil")
    func givenTimestampNotGreaterThanCurrent_whenWatermark_thenNil() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "old",
                     timestamp: Date(timeIntervalSince1970: 500), hasDeviceTimestamp: true),
        ]
        #expect(BLEEventHandler.nextEventLogWatermark(current: 1000, logs: logs, now: now) == nil)
    }

    // MARK: - live vs replay processing (A2)

    @Test("given same-second events, when processed live, then both survive but a replay watermark would drop them")
    func givenSameSecondEvents_whenLive_thenKeptButReplayDrops() {
        let t = Date(timeIntervalSince1970: 1000)
        let logs = [
            EventLog(eventType: .selectedTaskChanged, taskId: "a", timestamp: t),
            EventLog(eventType: .completeTask, taskId: "a", timestamp: t, hasDeviceTimestamp: true),
        ]
        // Live path applies no high-watermark filter: both survive (distinct content keys).
        #expect(BLEEventHandler.sortAndDedup(logs).count == 2)
        // Replay path with watermark already at t: strict-greater filter drops both at == t.
        #expect(BLEEventHandler.filterAndSortForMutation(logs, since: 1000).isEmpty)
    }

    @Test("given a newer live event, when an older batch is replayed, then the replay is still applied")
    @MainActor
    func givenNewerLiveEvent_whenOlderBatchReplays_thenReplayIsApplied() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let originalWatermark = await storage.loadLastEventLogTimestamp()
            let originalLogs = try await storage.loadEventLogs() ?? []

            await storage.saveLastEventLogTimestamp(0)

            let liveEvent = EventLog(
                eventType: .selectedTaskChanged,
                taskId: "live-event",
                timestamp: Date(timeIntervalSince1970: 200),
                hasDeviceTimestamp: true
            )
            let focusService = FocusSessionService.makeForTesting(
                focusGuardService: BLEEventHandlerMockFocusGuardService(),
                persistenceEnabled: false
            )

            await BLEEventHandler.handleEventLogs(
                [liveEvent],
                service: BLEService.shared,
                focusService: focusService,
                isReplay: false
            )

            var liveEventWasPersisted = false
            for _ in 0..<100 {
                let persisted = try await storage.loadEventLogs() ?? []
                if persisted.contains(where: { $0.id == liveEvent.id }) {
                    liveEventWasPersisted = true
                    break
                }
                await Task.yield()
            }
            #expect(liveEventWasPersisted)

            // Let the persistence task finish any work queued after writing the log file.
            for _ in 0..<10 {
                await Task.yield()
            }
            #expect(await storage.loadLastEventLogTimestamp() == 0)

            let replayedEvent = EventLog(
                eventType: .selectedTaskChanged,
                taskId: "replayed-event",
                timestamp: Date(timeIntervalSince1970: 150),
                hasDeviceTimestamp: true
            )
            let processedReplay = await BLEEventHandler.handleEventLogs(
                [replayedEvent],
                service: BLEService.shared,
                focusService: focusService,
                isReplay: true
            )

            #expect(processedReplay.contains { $0.id == replayedEvent.id })

            var replayWatermark: UInt32?
            for _ in 0..<100 {
                replayWatermark = await storage.loadLastEventLogTimestamp()
                if replayWatermark == 150 { break }
                await Task.yield()
            }
            #expect(replayWatermark == 150)

            try await storage.saveEventLogs(originalLogs)
            if let originalWatermark {
                await storage.saveLastEventLogTimestamp(originalWatermark)
            } else {
                UserDefaults.standard.removeObject(forKey: "lastEventLogTimestamp")
            }
        }
    }

    @Test("Concurrent event-log appends do not lose live logs or regress the replay watermark")
    func concurrentPersistenceIsAtomicAndMonotonic() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let originalWatermark = await storage.loadLastEventLogTimestamp()
            let originalLogs = try await storage.loadEventLogs() ?? []
            let first = EventLog(
                eventType: .selectedTaskChanged,
                taskId: "atomic-first",
                timestamp: Date(timeIntervalSince1970: 100),
                hasDeviceTimestamp: true
            )
            let second = EventLog(
                eventType: .selectedTaskChanged,
                taskId: "atomic-second",
                timestamp: Date(timeIntervalSince1970: 200),
                hasDeviceTimestamp: true
            )

            try await storage.saveEventLogs([])
            await storage.saveLastEventLogTimestamp(0)

            async let firstAppend: Void = storage.appendEventLogs(
                [first],
                isReplay: false,
                replayWatermarkCandidate: nil
            )
            async let secondAppend: Void = storage.appendEventLogs(
                [second],
                isReplay: false,
                replayWatermarkCandidate: nil
            )
            _ = try await (firstAppend, secondAppend)

            let persistedIDs = Set(try await storage.loadEventLogs()?.map(\.id) ?? [])
            #expect(persistedIDs == [first.id, second.id])

            async let newerReplay: Void = storage.appendEventLogs(
                [second],
                isReplay: true,
                replayWatermarkCandidate: 200
            )
            async let olderReplay: Void = storage.appendEventLogs(
                [first],
                isReplay: true,
                replayWatermarkCandidate: 100
            )
            _ = try await (newerReplay, olderReplay)
            #expect(await storage.loadLastEventLogTimestamp() == 200)

            try await storage.saveEventLogs(originalLogs)
            if let originalWatermark {
                await storage.saveLastEventLogTimestamp(originalWatermark)
            } else {
                UserDefaults.standard.removeObject(forKey: "lastEventLogTimestamp")
            }
        }
    }

    // MARK: - Codable backward compatibility (A1)

    /// Mirrors the pre-A1 on-disk shape (no hasDeviceTimestamp field), encoded with the same
    /// JSONEncoder so the Date format matches whatever the default strategy produces.
    private struct LegacyEventLog: Encodable {
        let id: UUID
        let eventType: String
        let taskId: String?
        let timestamp: Date
        let value: Int
    }

    @Test("given legacy event_logs JSON without hasDeviceTimestamp, when decoded, then it defaults to false")
    func givenLegacyJSONWithoutFlag_whenDecoded_thenDefaultsFalse() throws {
        let legacy = LegacyEventLog(id: UUID(), eventType: "complete_task", taskId: "t",
                                    timestamp: Date(timeIntervalSince1970: 1000), value: 0)
        let data = try JSONEncoder().encode(legacy)

        let decoded = try JSONDecoder().decode(EventLog.self, from: data)

        #expect(decoded.hasDeviceTimestamp == false)
        #expect(decoded.eventType == .completeTask)
        #expect(decoded.taskId == "t")
    }

    @Test("given an EventLog with hasDeviceTimestamp true, when round-tripped through Codable, then the flag is preserved")
    func givenFlagTrue_whenRoundTripped_thenPreserved() throws {
        let original = EventLog(eventType: .completeTask, taskId: "t",
                                timestamp: Date(timeIntervalSince1970: 1000), hasDeviceTimestamp: true)
        let data = try JSONEncoder().encode(original)

        let decoded = try JSONDecoder().decode(EventLog.self, from: data)

        #expect(decoded.hasDeviceTimestamp == true)
    }

    // MARK: - focusEventTimestamp future-skew clamp (focus-time / energy-bottle integrity)

    @Test("given a future-skewed device timestamp, when clamped for a focus event, then it is pinned to now")
    func givenFutureTimestamp_whenClamped_thenPinnedToNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // A firmware RTC glitch (or a forged unsigned frame) lands the session end years ahead.
        let future = Date(timeIntervalSince1970: 1_700_000_000 + (5 * 365 * 24 * 60 * 60))
        #expect(BLEEventHandler.focusEventTimestamp(future, now: now) == now)
    }

    @Test("given a normal past device timestamp, when clamped for a focus event, then it is left untouched")
    func givenPastTimestamp_whenClamped_thenUnchanged() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = Date(timeIntervalSince1970: 1_699_999_000)
        #expect(BLEEventHandler.focusEventTimestamp(past, now: now) == past)
    }

    @Test("given a device timestamp equal to now, when clamped, then it is preserved exactly")
    func givenTimestampEqualToNow_whenClamped_thenPreserved() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(BLEEventHandler.focusEventTimestamp(now, now: now) == now)
    }
}

@MainActor
private final class BLEEventHandlerMockFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .notDetermined
    var isDeepFocusFeatureEnabled = false
    var isDeepFocusCapable = false
    var canShowDeepFocusEntry: Bool { false }
    var selectedApplicationCount = 0
    var isPickerPresented = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { .notDetermined }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}

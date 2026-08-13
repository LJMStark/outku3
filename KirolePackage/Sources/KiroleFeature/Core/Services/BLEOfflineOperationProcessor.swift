import Foundation

/// Applies one `0x25 OP_BATCH` record behind a durable outer write-ahead ledger. The original
/// EventLog business processor remains authoritative for task/focus mutations; this layer adds
/// the protocol-required BootSession identity and cumulative-ACK durability boundary.
@MainActor
enum BLEOfflineOperationProcessor {
    typealias ApplyOperation = @MainActor (
        _ event: EventLog,
        _ scopedDeviceID: String
    ) async -> Bool

    static func process(
        _ record: OfflineSyncOperationRecord,
        deviceID: String,
        bootSessionID: UInt32,
        ledger: OfflineOperationLedger = .shared,
        apply: ApplyOperation? = nil
    ) async -> Bool {
        guard isSupportedOfflineEvent(record.eventType) else {
            let eventTypeHex = String(format: "%02X", record.eventType)
            ErrorReporter.log(
                .sync(
                    component: "BLE OfflineSync OP_BATCH",
                    underlying: "skipped unsupported event type 0x\(eventTypeHex) at operation \(record.operationID)"
                ),
                context: "BLEOfflineOperationProcessor.process"
            )
            return true
        }

        guard hasExactPayloadLength(record),
              let event = EventLog.fromBLEPayload(
                type: record.eventType,
                payload: record.originalPayload
              ) else {
            return false
        }

        if event.eventType == .completeTask || event.eventType == .skipTask {
            guard event.operationID == record.operationID else { return false }
        }

        let reservation = await ledger.reserve(
            deviceID: deviceID,
            bootSessionID: bootSessionID,
            operationID: record.operationID,
            eventType: record.eventType,
            originalPayload: record.originalPayload
        )
        switch reservation {
        case .duplicate:
            return true
        case .conflict, .unavailable:
            return false
        case .new, .resume:
            break
        }

        let scopedDeviceID = "\(deviceID)|boot=\(bootSessionID)"
        let applied = if let apply {
            await apply(event, scopedDeviceID)
        } else {
            await applyToApp(event, scopedDeviceID: scopedDeviceID)
        }
        guard applied else { return false }

        return await ledger.commit(
            deviceID: deviceID,
            bootSessionID: bootSessionID,
            operationID: record.operationID,
            eventType: record.eventType,
            originalPayload: record.originalPayload
        )
    }

    private static func isSupportedOfflineEvent(_ eventType: UInt8) -> Bool {
        switch EventLogType(rawByte: eventType) {
        case .completeTask, .skipTask, .reminderAcknowledged, .reminderDismissed:
            return true
        default:
            return false
        }
    }

    private static func hasExactPayloadLength(_ record: OfflineSyncOperationRecord) -> Bool {
        switch EventLogType(rawByte: record.eventType) {
        case .reminderAcknowledged, .reminderDismissed:
            return record.originalPayload.count == MemoryLayout<UInt32>.size
        default:
            return true
        }
    }

    private static func applyToApp(
        _ event: EventLog,
        scopedDeviceID: String
    ) async -> Bool {
        if event.eventType == .completeTask || event.eventType == .skipTask {
            await AppState.shared.ensureInitialLoadComplete()
        }
        let processing = await BLEEventHandler.processEventLogs(
            [event],
            service: BLEService.shared,
            isReplay: true,
            lastTimestampOverride: 0,
            persistLogs: false,
            deviceIDOverride: scopedDeviceID
        )
        guard processing.logs.count == 1 else { return false }

        if event.eventType == .completeTask || event.eventType == .skipTask {
            guard processing.taskOperationReceipts.count == 1,
                  processing.taskOperationReceipts[0].result != .internalError else {
                return false
            }
        }

        do {
            let watermark = BLEEventHandler.nextEventLogWatermark(
                current: 0,
                logs: [event],
                now: Date()
            )
            try await LocalStorage.shared.appendEventLogs(
                [event],
                isReplay: true,
                replayWatermarkCandidate: watermark
            )
            return true
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "event_logs.json",
                    underlying: error.localizedDescription
                ),
                context: "BLEOfflineOperationProcessor.applyToApp"
            )
            return false
        }
    }
}

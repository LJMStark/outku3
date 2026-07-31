import Foundation

// MARK: - Event Log batch / record parsing

extension BLEEventHandler {
    /// 解析 Event Log 记录 (使用新的 BLE payload 格式)
    /// data 的第一个字节为 event type，其余为 payload
    public static func parseEventLogRecord(from data: Data) -> EventLog? {
        guard !data.isEmpty else { return nil }
        let typeByte = data[0]
        let payload = data.count > 1 ? data.subdata(in: 1..<data.count) : Data()
        return EventLog.fromBLEPayload(type: typeByte, payload: payload)
    }

    /// 解析 Event Log 批次 payload:
    /// count(1B) + N 条记录，每条记录格式为 eventType(1B) + eventPayload(NB)
    static func parseEventLogBatchPayload(_ payload: Data) -> [EventLog] {
        guard !payload.isEmpty else { return [] }
        let count = Int(payload[0])
        var offset = 1
        var logs: [EventLog] = []

        for _ in 0..<count {
            guard offset < payload.count else { return [] }
            guard let recordLength = eventLogRecordLength(in: payload, offset: offset) else {
                return []
            }
            guard payload.count >= offset + recordLength else { return [] }

            let record = payload.subdata(in: offset..<(offset + recordLength))
            if let eventLog = parseEventLogRecord(from: record) {
                logs.append(eventLog)
            } else {
                return []
            }
            offset += recordLength
        }

        guard logs.count == count, offset == payload.count else { return [] }
        return logs
    }

    static func eventLogRecordLength(in payload: Data, offset: Int) -> Int? {
        guard offset < payload.count else { return nil }
        let type = payload[offset]

        switch type {
        case 0x01...0x06, 0x31:
            return 1
        case 0x30:
            // type(1B) + BatteryLevel(1B), v2.3.0+。协议 v2.5.19 的固件版本 3 字节
            // 只存在于实时 0x30 通知，批量记录恒为 2B（§5.15）——这里不读版本。
            return 2
        case 0x18, 0x40:
            return 2
        case 0x16, 0x17:
            return 5
        case 0x10:
            guard offset + 1 < payload.count else { return nil }
            let idLength = Int(payload[offset + 1])
            return 2 + idLength + 4
        case 0x11, 0x12:
            // type | SubVersion(1) | OperationID(4) | TaskIdLength(1) | TaskId | Timestamp(4)
            guard offset + 6 < payload.count, payload[offset + 1] == 0x01 else { return nil }
            let idLength = Int(payload[offset + 6])
            guard payload.bigEndianUInt32(at: offset + 2) != 0,
                  (1...36).contains(idLength) else { return nil }
            return 11 + idLength
        case 0x13...0x15:
            guard offset + 1 < payload.count else { return nil }
            let idLength = Int(payload[offset + 1])
            return 2 + idLength
        default:
            return nil
        }
    }
}

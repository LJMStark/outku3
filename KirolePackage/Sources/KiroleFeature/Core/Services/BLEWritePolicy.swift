// MARK: - BLE Write Policy

/// BLE 出站写入的纯状态判定。
///
/// 业务帧只能在连接完成后发送。安全握手是唯一例外：它发生在 CoreBluetooth
/// 已连上、但应用状态仍为 `.connecting` 的窗口内。
enum BLEWritePolicy {
    static func canWrite(state: BLEConnectionState, packetType: UInt8) -> Bool {
        switch state {
        case .connected:
            return true
        case .connecting:
            return packetType == BLEDataType.securityHandshake.rawValue
        case .disconnected, .scanning, .error:
            return false
        }
    }
}

// MARK: - Stale Write ACK Filter

/// 写超时后迟到 ACK 的丢弃记账。
///
/// 写 A 超时被弃 → writeGate 放行写 B 装入新 continuation → A 的迟到
/// `didWriteValueFor` 到达时槽里是 B 的 continuation，会用 A 的旧 ACK 提前完成 B。
/// ATT 每连接单在途 Write Request、CoreBluetooth 顺序回调且一写一回，加上
/// writeGate 单飞，所以计数 > 0 时下一个 ACK 必属最早被弃的写，丢弃即可。
/// ACK 不跨连接，断连清理时必须 `reset()`。
struct BLEStaleWriteAckFilter {
    private(set) var pendingStaleAcks = 0

    /// 写超时放弃等待时调用：它的 ACK 之后仍可能到达。
    mutating func markAbandonedWrite() {
        pendingStaleAcks += 1
    }

    /// 每个入站写 ACK 先问这里；返回 true 表示这是被弃写的迟到 ACK，直接丢弃。
    mutating func shouldDropIncomingAck() -> Bool {
        guard pendingStaleAcks > 0 else { return false }
        pendingStaleAcks -= 1
        return true
    }

    mutating func reset() {
        pendingStaleAcks = 0
    }
}

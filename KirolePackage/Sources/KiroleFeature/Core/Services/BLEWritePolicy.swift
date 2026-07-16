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

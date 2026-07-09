import Foundation

// MARK: - Firmware Version

/// 设备固件版本（Major.Minor.Patch 三段式），由 `DeviceWake(0x30)` 实时通知携带
/// （协议 v2.5.19+，BatteryLevel 后追加 3 字节，各段 0-255）。
/// 批量补传 `0x21` 中的 0x30 记录不含版本字节——版本只在实时帧出现。
public struct FirmwareVersion: Codable, Equatable, Sendable, CustomStringConvertible {
    public let major: UInt8
    public let minor: UInt8
    public let patch: UInt8

    public init(major: UInt8, minor: UInt8, patch: UInt8) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

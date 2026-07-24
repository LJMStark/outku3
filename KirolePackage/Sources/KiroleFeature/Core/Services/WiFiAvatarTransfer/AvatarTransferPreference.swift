import Foundation

/// 自定义头像传输通道偏好。默认 WiFi 优先（失败自动回退 BLE）。
public enum AvatarTransferPreference: String, Sendable, CaseIterable {
    /// WiFi 优先，失败回退 BLE（预留将来更智能的自动策略；当前与 wifiPreferred 等价）。
    case auto
    /// WiFi 优先，失败回退 BLE。
    case wifiPreferred
    /// 只用 BLE 分包传输（调试 / 确认 WiFi 不可用时）。
    case bleOnly

    private static let storageKey = "avatarTransferPreference"

    public static func load() -> AvatarTransferPreference {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AvatarTransferPreference(rawValue: raw) else {
            return .wifiPreferred
        }
        return value
    }

    public func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}

import Foundation

public actor BLEDeviceIdentityStore {
    public static let shared = BLEDeviceIdentityStore()

    private enum Keys {
        static let trustedDeviceIDs = "ble.trusted.device.ids"
        static let blockedDeviceIDs = "ble.blocked.device.ids"
    }

    private let defaults = UserDefaults.standard

    public func hasTrustedDevices() -> Bool {
        !trustedDeviceIDs().isEmpty
    }

    public func isTrusted(_ id: UUID) -> Bool {
        trustedDeviceIDs().contains(id.uuidString)
    }

    public func trust(_ id: UUID) {
        var trusted = trustedDeviceIDs()
        trusted.insert(id.uuidString)
        defaults.set(Array(trusted), forKey: Keys.trustedDeviceIDs)
    }

    public func isBlocked(_ id: UUID) -> Bool {
        blockedDeviceIDs().contains(id.uuidString)
    }

    public func block(_ id: UUID) {
        var blocked = blockedDeviceIDs()
        blocked.insert(id.uuidString)
        defaults.set(Array(blocked), forKey: Keys.blockedDeviceIDs)
    }

    private func trustedDeviceIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Keys.trustedDeviceIDs) ?? [])
    }

    private func blockedDeviceIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Keys.blockedDeviceIDs) ?? [])
    }
}

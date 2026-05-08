import Foundation

public actor BLEDeviceIdentityStore {
    public static let shared = BLEDeviceIdentityStore()

    private enum Keys {
        static let trustedDeviceIDs = "ble.trusted.device.ids"
        static let blockedDeviceIDs = "ble.blocked.device.ids"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    init(defaultsSuiteName: String) {
        self.defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }

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

    public func trustedDeviceCount() -> Int {
        trustedDeviceIDs().count
    }

    public func isBlocked(_ id: UUID) -> Bool {
        blockedDeviceIDs().contains(id.uuidString)
    }

    public func block(_ id: UUID) {
        var blocked = blockedDeviceIDs()
        blocked.insert(id.uuidString)
        defaults.set(Array(blocked), forKey: Keys.blockedDeviceIDs)
    }

    public func blockedDeviceCount() -> Int {
        blockedDeviceIDs().count
    }

    public func clearDeviceIdentities() {
        defaults.removeObject(forKey: Keys.trustedDeviceIDs)
        defaults.removeObject(forKey: Keys.blockedDeviceIDs)
    }

    private func trustedDeviceIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Keys.trustedDeviceIDs) ?? [])
    }

    private func blockedDeviceIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Keys.blockedDeviceIDs) ?? [])
    }
}

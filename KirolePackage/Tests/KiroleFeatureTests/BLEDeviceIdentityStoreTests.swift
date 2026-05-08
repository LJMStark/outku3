import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLE Device Identity Store Tests")
struct BLEDeviceIdentityStoreTests {
    @Test("Clearing device identities removes trusted and blocked devices")
    func clearDeviceIdentities() async throws {
        let suiteName = "BLEDeviceIdentityStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = BLEDeviceIdentityStore(defaultsSuiteName: suiteName)
        let trustedID = UUID()
        let blockedID = UUID()

        await store.trust(trustedID)
        await store.block(blockedID)

        #expect(await store.hasTrustedDevices())
        #expect(await store.isTrusted(trustedID))
        #expect(await store.isBlocked(blockedID))
        #expect(await store.trustedDeviceCount() == 1)
        #expect(await store.blockedDeviceCount() == 1)

        await store.clearDeviceIdentities()

        #expect(await !store.hasTrustedDevices())
        #expect(await !store.isTrusted(trustedID))
        #expect(await !store.isBlocked(blockedID))
        #expect(await store.trustedDeviceCount() == 0)
        #expect(await store.blockedDeviceCount() == 0)
    }
}

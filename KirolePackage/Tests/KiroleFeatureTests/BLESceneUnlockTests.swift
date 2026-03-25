import Testing
import Foundation
@testable import KiroleFeature

@Suite("BLE Scene Unlock Tests")
struct BLESceneUnlockTests {
    
    @Test("Verify BLE packet encoding for scene unlock")
    func testBLESceneUnlockCommand() {
        let packet = BLEPacketizer.buildSceneUnlockPacket(sceneId: 1)
        #expect(packet.count == 4)
        #expect(packet[3] == 1)
    }
}

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

    @Test("Screensaver packet encodes scene quote author and postcard day")
    func testScreensaverPacketEncoding() {
        let quote = "Rest with your progress."
        let author = "Nova"
        let config = ScreensaverConfig(
            type: .postcard,
            quote: quote,
            author: author,
            sceneId: DisplayScene.nightCity.rawValue,
            postcardDay: 7
        )

        let packet = BLEPacketizer.buildScreensaverPacket(config: config)
        let quoteData = Data(quote.utf8)
        let authorData = Data(author.utf8)

        #expect(packet.count == 8 + quoteData.count + authorData.count)
        #expect(packet[0] == 0xAA)
        #expect(packet[1] == 0x01)
        #expect(packet[2] == 0x02)
        #expect(packet[3] == 0x01)
        #expect(packet[4] == DisplayScene.nightCity.commandByte)
        #expect(packet[5] == 7)
        #expect(packet[6] == UInt8(quoteData.count))
        #expect(packet.subdata(in: 7..<(7 + quoteData.count)) == quoteData)
        #expect(packet[7 + quoteData.count] == UInt8(authorData.count))
        #expect(packet.suffix(authorData.count) == authorData)
    }
}

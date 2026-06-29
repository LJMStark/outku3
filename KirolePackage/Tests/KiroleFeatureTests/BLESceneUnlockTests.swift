import Testing
import Foundation
@testable import KiroleFeature

@Suite("BLE Scene Unlock Tests")
struct BLESceneUnlockTests {
    
    @Test("Scene unlock frame (0x17) encodes the scene command byte")
    func sceneUnlockFrameEncoding() {
        // v2.5.11: payload only — single SceneId byte. `writeData(type: .sceneUnlock, …)`
        // adds the Type+Length business wrapper (SecureEnvelope in secure mode). 见协议 §4.16。
        let payload = BLEDataEncoder.encodeSceneUnlock(.forest)
        #expect(payload.count == 1)
        #expect(payload[0] == DisplayScene.forest.commandByte)
    }

    @Test("Screensaver frame (0x16) encodes content type, scene, postcard day, quote, author")
    func screensaverFrameEncoding() {
        let quote = "Rest with your progress."
        let author = "Nova"
        let config = ScreensaverConfig(
            type: .postcard,
            quote: quote,
            author: author,
            sceneId: DisplayScene.nightCity.rawValue,
            postcardDay: 7
        )

        // v2.5.10: payload only — no `0xAA` dev header. `writeData(type: .screensaver, …)`
        // adds the Type+Length business wrapper (SecureEnvelope in secure mode). 见协议 §4.15。
        let payload = BLEDataEncoder.encodeScreensaver(config)
        let quoteData = Data(quote.utf8)
        let authorData = Data(author.utf8)

        // ContentType(1) | SceneByte(1) | PostcardDay(1) | QuoteLen(1)+Quote | AuthorLen(1)+Author
        #expect(payload.count == 5 + quoteData.count + authorData.count)
        #expect(payload[0] == 0x01)                                   // postcard
        #expect(payload[1] == DisplayScene.nightCity.commandByte)
        #expect(payload[2] == 7)                                      // postcard day
        #expect(payload[3] == UInt8(quoteData.count))
        #expect(payload.subdata(in: 4..<(4 + quoteData.count)) == quoteData)
        #expect(payload[4 + quoteData.count] == UInt8(authorData.count))
        #expect(payload.suffix(authorData.count) == authorData)
    }
}

import Foundation
import Testing
@testable import KiroleFeature

@Suite("Spectra6 quantizer")
struct Spectra6QuantizerTests {

    @Test("Primary RGB samples map to the expected Spectra 6 color")
    func nearestColorMapsPrimaries() {
        #expect(AvatarImageProcessor.findNearestColor(r: 0, g: 0, b: 0).color == .black)
        #expect(AvatarImageProcessor.findNearestColor(r: 255, g: 255, b: 255).color == .white)
        #expect(AvatarImageProcessor.findNearestColor(r: 250, g: 230, b: 10).color == .yellow)
        #expect(AvatarImageProcessor.findNearestColor(r: 250, g: 20, b: 20).color == .red)
        #expect(AvatarImageProcessor.findNearestColor(r: 10, g: 60, b: 200).color == .blue)
        #expect(AvatarImageProcessor.findNearestColor(r: 0, g: 150, b: 60).color == .green)
    }

    @Test("Nearest color never resolves to the reserved 0x4 slot")
    func nearestColorNeverReserved() {
        // EInkColor has no 0x4 case, so the palette can never produce it — this guards the
        // wire encoder by construction (no runtime assertion needed on the encode side).
        for r in stride(from: CGFloat(0), through: 255, by: 51) {
            for g in stride(from: CGFloat(0), through: 255, by: 51) {
                for b in stride(from: CGFloat(0), through: 255, by: 51) {
                    #expect(AvatarImageProcessor.findNearestColor(r: r, g: g, b: b).color.rawValue != 0x4)
                }
            }
        }
    }
}

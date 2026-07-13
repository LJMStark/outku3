import Foundation
import CoreGraphics
import Testing
@testable import KiroleFeature

// AvatarImageProcessor 纯逻辑测试（v2.5.24 PNG 管线）：
// fitSize 等比装框、isPNGData 魔数护栏、收缩循环终止性。
// UIKit 渲染路径（process/renderPNG）按 #if canImport(UIKit) 隔离，
// macOS `swift test` 只覆盖这里的纯函数——这正是把它们放在 UIKit 块外的原因。
@Suite("AvatarImageProcessor Pure Logic")
struct AvatarImageProcessorTests {

    // MARK: - fitSize

    @Test("fitSize downscales extreme landscape into the 800-wide bound")
    func fitSizeExtremeLandscape() {
        let result = AvatarImageProcessor.fitSize(original: CGSize(width: 4000, height: 100))
        #expect(result == CGSize(width: 800, height: 20))
    }

    @Test("fitSize downscales extreme portrait into the 700-tall bound")
    func fitSizeExtremePortrait() {
        let result = AvatarImageProcessor.fitSize(original: CGSize(width: 100, height: 4000))
        #expect(result == CGSize(width: 17, height: 700)) // 17.5 floor 取整
    }

    @Test("fitSize keeps an exact-bounds image unchanged")
    func fitSizeExactBounds() {
        let result = AvatarImageProcessor.fitSize(original: CGSize(width: 800, height: 700))
        #expect(result == CGSize(width: 800, height: 700))
    }

    @Test("fitSize shaves a one-pixel overflow while preserving ratio")
    func fitSizeOnePixelOverflow() {
        let result = AvatarImageProcessor.fitSize(original: CGSize(width: 801, height: 700))
        #expect(result == CGSize(width: 800, height: 699))
    }

    @Test("fitSize never upscales a smaller image")
    func fitSizeNoUpscale() {
        let result = AvatarImageProcessor.fitSize(original: CGSize(width: 400, height: 300))
        #expect(result == CGSize(width: 400, height: 300))
    }

    @Test("fitSize bounds a large landscape by height when height ratio is tighter")
    func fitSizeHeightBound() {
        let result = AvatarImageProcessor.fitSize(original: CGSize(width: 1600, height: 1500))
        #expect(result == CGSize(width: 746, height: 700))
    }

    @Test("fitSize bounds a large square by the 700 height")
    func fitSizeLargeSquare() {
        let result = AvatarImageProcessor.fitSize(original: CGSize(width: 5000, height: 5000))
        #expect(result == CGSize(width: 700, height: 700))
    }

    @Test("fitSize defends against degenerate zero sizes")
    func fitSizeZeroDefense() {
        #expect(AvatarImageProcessor.fitSize(original: .zero) == CGSize(width: 1, height: 1))
        #expect(AvatarImageProcessor.fitSize(original: CGSize(width: 1, height: 1)) == CGSize(width: 1, height: 1))
    }

    // MARK: - isPNGData（旧 4bpp 资产护栏）

    @Test("isPNGData accepts the 8-byte PNG signature with and without payload")
    func isPNGDataAccepts() {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(AvatarImageProcessor.isPNGData(Data(signature)))
        #expect(AvatarImageProcessor.isPNGData(Data(signature + [0x00, 0x00, 0x00, 0x0D])))
    }

    @Test("isPNGData rejects legacy 4bpp bytes, JPEG, truncated signature, and empty data")
    func isPNGDataRejects() {
        // 真实旧 4bpp 头（packPixelPair 输出，nibble 恒 ≤0x6，永远不可能是 0x89）
        #expect(!AvatarImageProcessor.isPNGData(Data([0x01, 0x35, 0x62])))
        #expect(!AvatarImageProcessor.isPNGData(Data([0xFF, 0xD8, 0xFF]))) // JPEG SOI
        #expect(!AvatarImageProcessor.isPNGData(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A]))) // 7 字节
        #expect(!AvatarImageProcessor.isPNGData(Data()))
    }

    // MARK: - 收缩循环终止性

    @Test("nextShrunkSize drives dimensions below the floor within the loop bound")
    func shrinkLoopTerminates() {
        var size = CGSize(width: 800, height: 700)
        var steps = 0
        while size.width > AvatarImageProcessor.minShrinkDimension,
              size.height > AvatarImageProcessor.minShrinkDimension {
            size = AvatarImageProcessor.nextShrunkSize(size)
            steps += 1
            #expect(steps <= 40, "×0.9 收缩循环应在 40 步内触及 50px 地板")
            if steps > 40 { break }
        }
        #expect(size.width >= 1)
        #expect(size.height >= 1)
    }

    @Test("nextShrunkSize never collapses below 1×1")
    func shrinkFloorsAtOnePixel() {
        let result = AvatarImageProcessor.nextShrunkSize(CGSize(width: 1, height: 1))
        #expect(result == CGSize(width: 1, height: 1))
    }
}

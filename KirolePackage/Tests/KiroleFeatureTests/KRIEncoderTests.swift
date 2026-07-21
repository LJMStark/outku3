import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import KiroleFeature

/// KRI v1 编码器测试（docs/KRI_图片转换规范.md）。核心是 §6 的 2×2 标准测试向量：
/// 直接比较完整 Data 可同时发现宽高端序、RGBA/BGRA 混淆、行方向和 alpha 处理错误。
/// PNG 全链路用 ImageIO 现造 PNG（macOS `swift test` 可跑，不依赖 UIKit）。
@Suite("KRI Encoder (v1)")
struct KRIEncoderTests {

    /// 规范 §6：top-down RGBA 输入（红/绿/蓝/半透明白）。
    private static let standardRGBA: [UInt8] = [
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   255, 255, 255, 128
    ]

    /// 规范 §6：期望的 28 字节 KRI 输出。
    private static let standardKRI = Data([
        0x4B, 0x52, 0x49, 0x01, 0x02, 0x00, 0x02, 0x00, 0x01, 0x01, 0x00, 0x00,
        0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0xFF,
        0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x80
    ])

    // MARK: - §6 标准测试向量

    @Test("2×2 标准向量：raw RGBA 缓冲区 → 逐字节等于规范 28 字节")
    func standardVectorFromRawBuffer() throws {
        let kri = try KRIEncoder.encode(width: 2, height: 2, straightRGBA: Self.standardRGBA)
        #expect(kri == Self.standardKRI)
    }

    @Test("2×2 标准向量：真 PNG 全链路（ImageIO 编→解）→ 同一 28 字节")
    func standardVectorFromPNG() throws {
        let png = try Self.makePNG(width: 2, height: 2, straightRGBA: Self.standardRGBA)
        let kri = try KRIEncoder.encode(pngData: png)
        #expect(kri == Self.standardKRI)
    }

    @Test("宽度 300 的小端编码：Width 字段为 2C 01")
    func widthLittleEndianBeyondOneByte() throws {
        let rgba = [UInt8](repeating: 0x7F, count: 300 * 2 * 4)
        let kri = try KRIEncoder.encode(width: 300, height: 2, straightRGBA: rgba)
        #expect(kri[4] == 0x2C)
        #expect(kri[5] == 0x01)
        #expect(kri[6] == 0x02)
        #expect(kri[7] == 0x00)
        #expect(kri.count == 12 + 300 * 2 * 4)
    }

    // MARK: - 错误路径

    @Test("非法尺寸：0 宽 / 超 UInt16 上限 → invalidSize")
    func invalidSizeThrows() {
        #expect(throws: KRIError.invalidSize) {
            try KRIEncoder.encode(width: 0, height: 2, straightRGBA: [])
        }
        #expect(throws: KRIError.invalidSize) {
            try KRIEncoder.encode(width: 65536, height: 1, straightRGBA: [])
        }
    }

    @Test("缓冲区长度与宽高不符 → invalidPixelBuffer")
    func bufferMismatchThrows() {
        #expect(throws: KRIError.invalidPixelBuffer) {
            try KRIEncoder.encode(width: 2, height: 2, straightRGBA: [0, 0, 0])
        }
    }

    @Test("非图片字节 → undecodableImage")
    func junkPNGThrows() {
        #expect(throws: KRIError.undecodableImage) {
            try KRIEncoder.encode(pngData: Data("not a png".utf8))
        }
    }

    // MARK: - §7 下发前校验

    @Test("isValidKRI：合法产物通过；截断/多尾字节/坏魔数/错 colorFormat/保留位非零全拒")
    func validationChecks() throws {
        let good = try KRIEncoder.encode(width: 2, height: 2, straightRGBA: Self.standardRGBA)
        #expect(KRIEncoder.isValidKRI(good))

        #expect(!KRIEncoder.isValidKRI(good.dropLast()))          // 少一字节
        #expect(!KRIEncoder.isValidKRI(good + Data([0x00])))      // 多一字节（规范：附加数据判无效）
        #expect(!KRIEncoder.isValidKRI(Data()))

        var badMagic = good
        badMagic[0] = 0x50
        #expect(!KRIEncoder.isValidKRI(badMagic))

        var badFormat = good
        badFormat[8] = 0x02
        #expect(!KRIEncoder.isValidKRI(badFormat))

        var badReserved = good
        badReserved[10] = 0x01
        #expect(!KRIEncoder.isValidKRI(badReserved))

        var zeroWidth = good
        zeroWidth[4] = 0x00
        zeroWidth[5] = 0x00
        #expect(!KRIEncoder.isValidKRI(zeroWidth))
    }

    // MARK: - 反预乘兜底

    @Test("unpremultiply：A=255 直通、A=0 清零、半透明白精确恢复、四舍五入")
    func unpremultiplyBehavior() {
        var opaque: [UInt8] = [200, 100, 50, 255]
        KRIEncoder.unpremultiply(&opaque)
        #expect(opaque == [200, 100, 50, 255])

        var transparent: [UInt8] = [7, 8, 9, 0]
        KRIEncoder.unpremultiply(&transparent)
        #expect(transparent == [0, 0, 0, 0])

        // 预乘半透明白 (128,128,128,128) → 直通 (255,255,255,128)，无损恢复
        var white: [UInt8] = [128, 128, 128, 128]
        KRIEncoder.unpremultiply(&white)
        #expect(white == [255, 255, 255, 128])

        // (100×255+100)/200 = 128：验证 +alpha/2 的四舍五入
        var rounded: [UInt8] = [100, 100, 100, 200]
        KRIEncoder.unpremultiply(&rounded)
        #expect(rounded[0] == 128)
    }

    // MARK: - Helpers

    /// 用 ImageIO 从 straight RGBA 造一张 sRGB PNG（CGImage 支持 straight alpha，
    /// PNG 格式本身只存 straight alpha——写读均无预乘损耗）。
    private static func makePNG(width: Int, height: Int, straightRGBA: [UInt8]) throws -> Data {
        guard let provider = CGDataProvider(data: Data(straightRGBA) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider, decode: nil,
                  shouldInterpolate: false, intent: .defaultIntent
              ) else {
            throw KRIError.undecodableImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.png" as CFString, 1, nil
        ) else {
            throw KRIError.undecodableImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw KRIError.undecodableImage
        }
        return output as Data
    }
}

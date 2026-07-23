import Foundation
import CoreGraphics
import ImageIO

// MARK: - KRI Error

/// 与 docs/KRI_图片转换规范.md §5 参考实现同名错误，便于对照规范排查。
public enum KRIError: Error, Equatable {
    case invalidSize
    case invalidPixelBuffer
    case undecodableImage
    case unsupportedImageFormat
}

// MARK: - KRI Encoder

/// PNG → KRI v1（Kirole Raw Image）转换器，逐条实现 docs/KRI_图片转换规范.md：
/// 12 字节小端文件头 + 左上角起始、逐行、直通（非预乘）alpha 的 BGRA 裸像素，
/// 无压缩、无行 padding、无尾部数据，总长恒为 `12 + width × height × 4`。
///
/// 传输通道（协议 v2.7 §4.12）：KRI bytes 放入
/// `CustomAvatarFrame (0x15, SubVersion 0x04)`，并与 OperationID、AvatarID、长度和
/// CRC 一起发送。旧 0x02 PNG 与 0x03 匿名 KRI 通道已删除。
///
/// 与 `AvatarImageProcessor` 一样不绑 main actor：Data 进 Data 出，800×700 图约
/// 2.2 MB 像素区，调用方应经 `Task.detached` 执行。本层会烘焙 PNG 方向元数据，
/// 但不做额外缩放、裁剪、旋转或抖动。
public enum KRIEncoder {

    /// `KRI\x01`（规范 §2 Magic）。
    static let magic: [UInt8] = [0x4B, 0x52, 0x49, 0x01]
    static let headerByteCount = 12
    /// Color format 字段固定值：ARGB8888。
    static let colorFormatARGB8888: UInt8 = 0x01
    static let formatVersion: UInt8 = 0x01

    // MARK: Pure encoding（规范 §5 参考实现）

    /// 将「左上角起始、逐行、直通 RGBA8888」缓冲区编码为完整 KRI v1 文件。
    /// 每像素写入顺序为 B、G、R、A（规范 §3）；不负责 PNG 解码。
    public static func encode(width: Int, height: Int, straightRGBA: [UInt8]) throws -> Data {
        guard width > 0, width <= Int(UInt16.max),
              height > 0, height <= Int(UInt16.max) else {
            throw KRIError.invalidSize
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (rgbaSize, sizeOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !sizeOverflow, straightRGBA.count == rgbaSize else {
            throw KRIError.invalidPixelBuffer
        }

        var output = Data(capacity: headerByteCount + rgbaSize)
        output.append(contentsOf: magic)
        output.append(UInt8(width & 0xFF))
        output.append(UInt8((width >> 8) & 0xFF))
        output.append(UInt8(height & 0xFF))
        output.append(UInt8((height >> 8) & 0xFF))
        output.append(colorFormatARGB8888)
        output.append(formatVersion)
        output.append(contentsOf: [0x00, 0x00]) // reserved

        var pixels = straightRGBA
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            pixels.swapAt(pixel, pixel + 2) // RGBA → BGRA
        }
        output.append(contentsOf: pixels)
        return output
    }

    // MARK: PNG → KRI（规范 §4 转换步骤）

    /// 解码 PNG 并编码为 KRI v1。优先直读解码器输出的 straight RGBA（规范 §5.1
    /// "应优先使用能直接输出 straight RGBA 的解码器"，且不经色彩管理改样本）；
    /// 解码器给出其他格式时退到 sRGB 预乘重绘 + 反预乘（±1 舍入，规范明示可接受）。
    public static func encode(pngData: Data) throws -> Data {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(pngData as CFData, options) else {
            throw KRIError.undecodableImage
        }
        guard let sourceType = CGImageSourceGetType(source) else {
            throw KRIError.undecodableImage
        }
        guard sourceType as String == "public.png" else {
            throw KRIError.unsupportedImageFormat
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw KRIError.undecodableImage
        }
        guard image.width > 0, image.width <= Int(UInt16.max),
              image.height > 0, image.height <= Int(UInt16.max) else {
            throw KRIError.invalidSize
        }
        guard let rgba = directStraightRGBA(from: image) ?? redrawnStraightRGBA(from: image) else {
            throw KRIError.undecodableImage
        }
        let oriented = applyingOrientation(
            imageOrientation(from: source),
            width: image.width,
            height: image.height,
            straightRGBA: rgba
        )
        return try encode(
            width: oriented.width,
            height: oriented.height,
            straightRGBA: oriented.rgba
        )
    }

    // MARK: Post-encode validation（规范 §7 下发前检查 1-6）

    /// 校验完整 KRI 文件：魔数、宽高非零、colorFormat/version、保留位清零、
    /// 总长严格等于 `12 + width × height × 4`（多一字节少一字节都判无效）。
    public static func isValidKRI(_ data: Data) -> Bool {
        guard data.count >= headerByteCount else { return false }
        let header = [UInt8](data.prefix(headerByteCount))
        guard Array(header[0..<4]) == magic else { return false }
        let width = Int(header[4]) | (Int(header[5]) << 8)
        let height = Int(header[6]) | (Int(header[7]) << 8)
        guard width > 0, height > 0,
              header[8] == colorFormatARGB8888,
              header[9] == formatVersion,
              header[10] == 0x00, header[11] == 0x00 else {
            return false
        }
        return data.count == headerByteCount + width * height * 4
    }

    // MARK: Decode helpers

    /// 快路径：解码结果已是 8-bit、RGB 色彩模型、straight alpha 末位、R,G,B,A 内存
    /// 序（byteOrderDefault / 32Big 对 8-bit 分量等价）→ 按行拷出，跳过 stride padding。
    /// PNG 本身只存 straight alpha，ImageIO 解码 PNG 通常命中此路径，逐字节无损。
    private static func directStraightRGBA(from image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 8 else { return nil }
        let byteOrder = image.bitmapInfo.intersection(.byteOrderMask)

        if image.bitsPerPixel == 32,
           image.colorSpace?.model == .rgb,
           image.alphaInfo == .last,
           byteOrder == [] || byteOrder == .byteOrder32Big {
            return tightlyPackedBytes(from: image, bytesPerPixel: 4)
        }

        if image.bitsPerPixel == 16,
           image.colorSpace?.model == .monochrome,
           image.alphaInfo == .last,
           byteOrder == [] || byteOrder == .byteOrder16Big,
           let grayAlpha = tightlyPackedBytes(from: image, bytesPerPixel: 2) {
            var rgba = [UInt8]()
            rgba.reserveCapacity(image.width * image.height * 4)
            for pixel in stride(from: 0, to: grayAlpha.count, by: 2) {
                let gray = grayAlpha[pixel]
                rgba.append(contentsOf: [gray, gray, gray, grayAlpha[pixel + 1]])
            }
            return rgba
        }

        return nil
    }

    private static func tightlyPackedBytes(from image: CGImage, bytesPerPixel: Int) -> [UInt8]? {
        guard let cfData = image.dataProvider?.data else { return nil }
        let source = cfData as Data
        let rowBytes = image.width * bytesPerPixel
        let rowStride = image.bytesPerRow
        guard image.height > 0,
              rowStride >= rowBytes,
              source.count >= rowStride * (image.height - 1) + rowBytes else {
            return nil
        }

        var pixels = [UInt8]()
        pixels.reserveCapacity(rowBytes * image.height)
        for row in 0..<image.height {
            let start = source.startIndex + row * rowStride
            pixels.append(contentsOf: source[start..<(start + rowBytes)])
        }
        return pixels
    }

    private static func imageOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let number = properties[kCGImagePropertyOrientation] as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: number.uint32Value) else {
            return .up
        }
        return orientation
    }

    private static func applyingOrientation(
        _ orientation: CGImagePropertyOrientation,
        width: Int,
        height: Int,
        straightRGBA: [UInt8]
    ) -> (width: Int, height: Int, rgba: [UInt8]) {
        guard orientation != .up else {
            return (width, height, straightRGBA)
        }

        let swapsAxes = switch orientation {
        case .leftMirrored, .right, .rightMirrored, .left: true
        default: false
        }
        let outputWidth = swapsAxes ? height : width
        let outputHeight = swapsAxes ? width : height
        var output = [UInt8](repeating: 0, count: straightRGBA.count)

        for outputY in 0..<outputHeight {
            for outputX in 0..<outputWidth {
                let sourcePoint: (x: Int, y: Int) = switch orientation {
                case .up:
                    (outputX, outputY)
                case .upMirrored:
                    (width - 1 - outputX, outputY)
                case .down:
                    (width - 1 - outputX, height - 1 - outputY)
                case .downMirrored:
                    (outputX, height - 1 - outputY)
                case .leftMirrored:
                    (outputY, outputX)
                case .right:
                    (outputY, height - 1 - outputX)
                case .rightMirrored:
                    (width - 1 - outputY, height - 1 - outputX)
                case .left:
                    (width - 1 - outputY, outputX)
                @unknown default:
                    (outputX, outputY)
                }
                let sourceOffset = (sourcePoint.y * width + sourcePoint.x) * 4
                let outputOffset = (outputY * outputWidth + outputX) * 4
                output[outputOffset] = straightRGBA[sourceOffset]
                output[outputOffset + 1] = straightRGBA[sourceOffset + 1]
                output[outputOffset + 2] = straightRGBA[sourceOffset + 2]
                output[outputOffset + 3] = straightRGBA[sourceOffset + 3]
            }
        }

        return (outputWidth, outputHeight, output)
    }

    /// 兜底路径：CGBitmapContext 不支持 straight-alpha 绘制，先绘入 sRGB 预乘
    /// RGBA 上下文（CGImage 绘制后内存首行即图片顶部，无需翻转），再反预乘。
    private static func redrawnStraightRGBA(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        unpremultiply(&pixels)
        return pixels
    }

    /// 预乘 RGBA → 直通 RGBA（四舍五入）。A=0 时 RGB 清零（预乘源里本就全零，
    /// 无原始色可恢复）；A=255 原样直通。
    static func unpremultiply(_ rgba: inout [UInt8]) {
        for pixel in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Int(rgba[pixel + 3])
            if alpha == 255 { continue }
            if alpha == 0 {
                rgba[pixel] = 0
                rgba[pixel + 1] = 0
                rgba[pixel + 2] = 0
                continue
            }
            for channel in pixel..<(pixel + 3) {
                rgba[channel] = UInt8(min(255, (Int(rgba[channel]) * 255 + alpha / 2) / alpha))
            }
        }
    }
}

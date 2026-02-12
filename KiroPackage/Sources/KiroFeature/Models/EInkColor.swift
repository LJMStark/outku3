import Foundation

// MARK: - E-Ink Spectra 6 Color

/// Spectra 6 颜色索引（4bpp 编码，每字节 2 像素）
public enum EInkColor: UInt8, CaseIterable, Sendable {
    case black  = 0x0
    case white  = 0x1
    case yellow = 0x2
    case red    = 0x3
    // 0x4 reserved
    case blue   = 0x5
    case green  = 0x6

    /// Pack two pixels into a single byte (high nibble = even pixel, low nibble = odd pixel)
    public static func packPixelPair(even: EInkColor, odd: EInkColor) -> UInt8 {
        (even.rawValue << 4) | odd.rawValue
    }

    /// Unpack a byte into two pixel colors
    public static func unpackPixelPair(_ byte: UInt8) -> (even: EInkColor, odd: EInkColor)? {
        guard let even = EInkColor(rawValue: byte >> 4),
              let odd = EInkColor(rawValue: byte & 0x0F) else {
            return nil
        }
        return (even, odd)
    }
}

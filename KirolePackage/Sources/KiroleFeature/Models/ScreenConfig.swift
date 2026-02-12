import Foundation

// MARK: - Screen Size Configuration

/// E-ink 屏幕尺寸配置
public enum ScreenSize: String, Codable, Sendable {
    case fourInch   // 4寸: 400 x 600, Spectra 6
    case sevenInch  // 7.3寸: 800 x 480, Spectra 6

    public var width: Int {
        switch self {
        case .fourInch: return 400
        case .sevenInch: return 800
        }
    }

    public var height: Int {
        switch self {
        case .fourInch: return 600
        case .sevenInch: return 480
        }
    }

    /// Total pixel count
    public var pixelCount: Int { width * height }

    /// Frame buffer size in bytes (4bpp = 2 pixels per byte)
    public var frameBufferSize: Int { pixelCount / 2 }

    /// Maximum number of top tasks displayed on the overview page
    public var maxTasks: Int {
        switch self {
        case .fourInch: return 3
        case .sevenInch: return 5
        }
    }

    /// Display label for UI
    public var displayName: String {
        switch self {
        case .fourInch: return "4\""
        case .sevenInch: return "7.3\""
        }
    }
}

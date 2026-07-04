import Foundation

// MARK: - Screen Size Configuration

/// E-ink 屏幕尺寸配置
public enum ScreenSize: String, Codable, Sendable {
    case fourInch   // 4寸: 768×552（横向使用；面板原生竖向 552×768 @237DPI）, Spectra 6
    case sevenInch  // 7.3寸: 1600×1200 @282DPI, Spectra 6

    // 分辨率真源 = docs/硬件需求文档 §4（2026-06-25/26 硬件确认）。旧值 400×600 / 800×480
    // 是早期面板型号，与实物不符——当时无 live 消费方所以没爆雷；将来接全屏图像帧时
    // frameBufferSize 若按旧值会欠算 5 倍导致帧截断/花屏（2026-07-04 审计 D1）。
    public var width: Int {
        switch self {
        case .fourInch: return 768
        case .sevenInch: return 1600
        }
    }

    public var height: Int {
        switch self {
        case .fourInch: return 552
        case .sevenInch: return 1200
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

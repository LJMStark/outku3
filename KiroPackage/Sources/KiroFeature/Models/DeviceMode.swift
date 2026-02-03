import Foundation

// MARK: - Device Mode

/// E-ink 设备的运行模式
public enum DeviceMode: String, Codable, Sendable, CaseIterable {
    /// 互动模式 - 完整功能，响应按键事件
    case interactive = "Interactive"
    /// 专注模式 - 简化显示，减少干扰
    case focus = "Focus"

    public var displayName: String {
        switch self {
        case .interactive: return "Interactive"
        case .focus: return "Focus"
        }
    }

    public var description: String {
        switch self {
        case .interactive:
            return "Full features with button interactions"
        case .focus:
            return "Simplified display, fewer distractions"
        }
    }

    public var iconName: String {
        switch self {
        case .interactive: return "hand.tap.fill"
        case .focus: return "moon.fill"
        }
    }
}

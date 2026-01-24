import SwiftUI

// MARK: - Theme System

public enum AppTheme: String, CaseIterable, Identifiable {
    case cream = "Cream"
    case sage = "Sage"
    case lavender = "Lavender"
    case peach = "Peach"
    case sky = "Sky"

    public var id: String { rawValue }

    public var colors: ThemeColors {
        switch self {
        case .cream:
            return ThemeColors(
                background: Color(hex: "FDF6E3"),
                cardBackground: Color(hex: "FFFEF9"),
                primaryText: Color(hex: "2D2D2D"),
                secondaryText: Color(hex: "8B8B8B"),
                accent: Color(hex: "E8B86D"),
                timeline: Color(hex: "E5DED3"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42"),
                taskComplete: Color(hex: "7CB342"),
                streakActive: Color(hex: "FF6B6B")
            )
        case .sage:
            return ThemeColors(
                background: Color(hex: "E8F0E8"),
                cardBackground: Color(hex: "F5FAF5"),
                primaryText: Color(hex: "2D3B2D"),
                secondaryText: Color(hex: "6B7B6B"),
                accent: Color(hex: "7CB342"),
                timeline: Color(hex: "C5D5C5"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42"),
                taskComplete: Color(hex: "7CB342"),
                streakActive: Color(hex: "FF6B6B")
            )
        case .lavender:
            return ThemeColors(
                background: Color(hex: "F0E8F5"),
                cardBackground: Color(hex: "FAF5FF"),
                primaryText: Color(hex: "3B2D4B"),
                secondaryText: Color(hex: "7B6B8B"),
                accent: Color(hex: "9B7BB8"),
                timeline: Color(hex: "D5C5E5"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42"),
                taskComplete: Color(hex: "7CB342"),
                streakActive: Color(hex: "FF6B6B")
            )
        case .peach:
            return ThemeColors(
                background: Color(hex: "FFF0E8"),
                cardBackground: Color(hex: "FFFAF5"),
                primaryText: Color(hex: "4B3B2D"),
                secondaryText: Color(hex: "8B7B6B"),
                accent: Color(hex: "FF8C42"),
                timeline: Color(hex: "E5D5C5"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42"),
                taskComplete: Color(hex: "7CB342"),
                streakActive: Color(hex: "FF6B6B")
            )
        case .sky:
            return ThemeColors(
                background: Color(hex: "E8F4FA"),
                cardBackground: Color(hex: "F5FAFF"),
                primaryText: Color(hex: "2D3B4B"),
                secondaryText: Color(hex: "6B7B8B"),
                accent: Color(hex: "4A90D9"),
                timeline: Color(hex: "C5D5E5"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42"),
                taskComplete: Color(hex: "7CB342"),
                streakActive: Color(hex: "FF6B6B")
            )
        }
    }

    public var previewColor: Color {
        colors.accent
    }
}

public struct ThemeColors: Sendable {
    public let background: Color
    public let cardBackground: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let accent: Color
    public let timeline: Color
    public let sunrise: Color
    public let sunset: Color
    public let taskComplete: Color
    public let streakActive: Color
}

// MARK: - Theme Environment

@Observable
public final class ThemeManager: @unchecked Sendable {
    public static let shared = ThemeManager()

    public var currentTheme: AppTheme = .cream

    public var colors: ThemeColors {
        currentTheme.colors
    }

    private init() {}

    public func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography

public enum AppTypography {
    public static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    public static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    public static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    public static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    public static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    public static let body = Font.system(size: 17, weight: .regular, design: .rounded)
    public static let callout = Font.system(size: 16, weight: .regular, design: .rounded)
    public static let subheadline = Font.system(size: 15, weight: .regular, design: .rounded)
    public static let footnote = Font.system(size: 13, weight: .regular, design: .rounded)
    public static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
    public static let caption2 = Font.system(size: 11, weight: .regular, design: .rounded)

    // Haiku specific
    public static let haiku = Font.system(size: 16, weight: .light, design: .serif)

    // Time display
    public static let timeDisplay = Font.system(size: 14, weight: .medium, design: .monospaced)
}

// MARK: - Spacing

public enum AppSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32
}

// MARK: - Corner Radius

public enum AppCornerRadius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let extraLarge: CGFloat = 20
    public static let pill: CGFloat = 100
}

import SwiftUI

// MARK: - Theme System

public enum AppTheme: String, CaseIterable, Identifiable {
    case classicWarm = "Classic Warm"
    case elegantPurple = "Elegant Purple"
    case modernTeal = "Modern Teal"

    public var id: String { rawValue }

    public var colors: ThemeColors {
        switch self {
        case .classicWarm:
            return ThemeColors(
                primary: Color(hex: "a67c52"),
                primaryDark: Color(hex: "8b6f47"),
                primaryLight: Color(hex: "d4a574"),
                accent: Color(hex: "4a5f4f"),
                accentLight: Color(hex: "d4e8e0"),
                accentDark: Color(hex: "3a4f3f"),
                background: Color(hex: "f5f1e8"),
                cardBackground: Color.white,
                primaryText: Color(hex: "1f2937"),
                secondaryText: Color(hex: "6b7280"),
                taskComplete: Color(hex: "4CAF50"),
                streakActive: Color(hex: "e8c17f"),
                timeline: Color(hex: "D1D5DB"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42")
            )
        case .elegantPurple:
            return ThemeColors(
                primary: Color(hex: "9b7bb5"),
                primaryDark: Color(hex: "7a5d8f"),
                primaryLight: Color(hex: "c4a7d9"),
                accent: Color(hex: "5f4a6f"),
                accentLight: Color(hex: "e8d4f0"),
                accentDark: Color(hex: "4a3555"),
                background: Color(hex: "f5f1f8"),
                cardBackground: Color.white,
                primaryText: Color(hex: "1f2937"),
                secondaryText: Color(hex: "6b7280"),
                taskComplete: Color(hex: "4CAF50"),
                streakActive: Color(hex: "c4a7d9"),
                timeline: Color(hex: "D1D5DB"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42")
            )
        case .modernTeal:
            return ThemeColors(
                primary: Color(hex: "5a9aa8"),
                primaryDark: Color(hex: "457a85"),
                primaryLight: Color(hex: "7ec4d4"),
                accent: Color(hex: "4a6f6f"),
                accentLight: Color(hex: "d4e8e8"),
                accentDark: Color(hex: "3a5555"),
                background: Color(hex: "f1f5f5"),
                cardBackground: Color.white,
                primaryText: Color(hex: "1f2937"),
                secondaryText: Color(hex: "6b7280"),
                taskComplete: Color(hex: "4CAF50"),
                streakActive: Color(hex: "7ec4d4"),
                timeline: Color(hex: "D1D5DB"),
                sunrise: Color(hex: "FFD93D"),
                sunset: Color(hex: "FF8C42")
            )
        }
    }

    public var headerGradient: LinearGradient {
        LinearGradient(
            colors: [colors.primary, colors.primaryDark],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public var cardGradient: LinearGradient {
        LinearGradient(
            colors: [colors.accentLight, colors.accentLight.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var previewColors: [Color] {
        [colors.primaryLight, colors.primaryDark, colors.accent]
    }
}

public struct ThemeColors: Sendable {
    public let primary: Color
    public let primaryDark: Color
    public let primaryLight: Color
    public let accent: Color
    public let accentLight: Color
    public let accentDark: Color
    public let background: Color
    public let cardBackground: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let taskComplete: Color
    public let streakActive: Color
    public let timeline: Color
    public let sunrise: Color
    public let sunset: Color
}

// MARK: - Theme Environment

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public var currentTheme: AppTheme = .classicWarm

    public var colors: ThemeColors {
        currentTheme.colors
    }

    private init() {}

    public func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }

    public func setTheme(index: Int) {
        guard index >= 0 && index < AppTheme.allCases.count else { return }
        currentTheme = AppTheme.allCases[index]
    }

    public var currentThemeIndex: Int {
        AppTheme.allCases.firstIndex(of: currentTheme) ?? 0
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

    public static let haiku = Font.system(size: 16, weight: .light, design: .serif)
    public static let timeDisplay = Font.system(size: 14, weight: .medium, design: .monospaced)

    // Reference code typography
    public static let sectionHeader = Font.system(size: 12, weight: .bold)
    public static let statLabel = Font.system(size: 12, weight: .bold)
    public static let statValue = Font.system(size: 15, weight: .semibold)
}

// MARK: - Spacing (matching Tailwind)

public enum AppSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24  // p-6
    public static let xxxl: CGFloat = 32
}

// MARK: - Corner Radius (matching Tailwind)

public enum AppCornerRadius {
    public static let small: CGFloat = 8      // rounded-lg
    public static let medium: CGFloat = 12    // rounded-xl
    public static let large: CGFloat = 16     // rounded-2xl
    public static let extraLarge: CGFloat = 24 // rounded-3xl
    public static let pill: CGFloat = 100
}

// MARK: - Shared Date Formatters

public enum AppDateFormatters {
    public static let headerDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM dd"
        return formatter
    }()

    public static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    public static let separatorDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    public static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

// MARK: - Card Style Modifier

public struct CardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let shadowOpacity: Double
    @Environment(ThemeManager.self) private var theme

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(theme.colors.cardBackground)
                    .shadow(color: .black.opacity(shadowOpacity), radius: 10, x: 0, y: 4)
            }
    }
}

public extension View {
    func cardStyle(cornerRadius: CGFloat = AppCornerRadius.extraLarge, shadowOpacity: Double = 0.08) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, shadowOpacity: shadowOpacity))
    }
}

public extension Animation {
    static let appStandard = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

// MARK: - Toggle Switch Style

public struct CustomToggleStyle: ToggleStyle {
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: 14)
                .fill(configuration.isOn ? Color(hex: "4CAF50") : Color(hex: "E0E0E0"))
                .frame(width: 48, height: 28)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 1)
                        .frame(width: 20, height: 20)
                        .offset(x: configuration.isOn ? 10 : -10)
                        .animation(Animation.appStandard, value: configuration.isOn)
                )
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

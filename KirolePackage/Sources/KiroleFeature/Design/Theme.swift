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
                primary: Color(hex: "B07432"),
                primaryDark: Color(hex: "96602A"),
                primaryLight: Color(hex: "D4A46A"),
                accent: Color(hex: "2C4637"),
                accentLight: Color(hex: "d4e8e0"),
                accentDark: Color(hex: "1B3224"),
                background: Color(hex: "F4F2EC"),
                cardBackground: Color.white,
                primaryText: Color(hex: "1f2937"),
                secondaryText: Color(hex: "6b7280"),
                taskComplete: Color(hex: "4CAF50"),
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
    public let timeline: Color
    public let sunrise: Color
    public let sunset: Color
}

// MARK: - Derived Semantic Tokens
//
// 由核心色板推导的语义 token。计算属性而非存储属性：三套主题自动保持同步，
// 不存在逐主题调色 drift 的问题，也不会破坏任何既有 ThemeColors 构造点。
// 视图里请优先用这些 token，不要再写裸 `Color(hex:)`：
//
//   border        — 卡片/面板细描边、sheet 拖动指示条
//   borderStrong  — 需要更清晰静态轮廓的控件（未勾选 checkbox 等）
//   warning       — 可恢复的同步告警（琥珀色，语义色，刻意不随主题变化）
public extension ThemeColors {
    /// 低透明墨色细线：在白卡和彩色底上都读得出，又足够安静。
    var border: Color { primaryText.opacity(0.10) }

    /// 控件级静态轮廓（未勾选 checkbox、输入框边框）。
    var borderStrong: Color { primaryText.opacity(0.24) }

    /// 告警琥珀：语义色，刻意保持跨主题一致（警示含义不应随皮肤改变）。
    var warning: Color { Color(hex: "D97706") }
}

// MARK: - Theme Environment

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    // 不加入 LocalStorage.resettableUserDefaultKeys：主题偏好不属于"重置本地数据"的范畴，
    // 且往 resettable keys 加 key 会引入并行测试隔离问题。
    private static let themeDefaultsKey = "kirole.selectedTheme"

    public var currentTheme: AppTheme = .classicWarm

    public var colors: ThemeColors {
        currentTheme.colors
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.themeDefaultsKey),
           let savedTheme = AppTheme(rawValue: raw) {
            currentTheme = savedTheme
        }
    }

    public func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.themeDefaultsKey)
    }

    public func setTheme(index: Int) {
        guard index >= 0 && index < AppTheme.allCases.count else { return }
        setTheme(AppTheme.allCases[index])
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
    private static let englishPOSIXLocale = Locale(identifier: "en_US_POSIX")

    private static func makeDateFormatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = englishPOSIXLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = dateFormat
        return formatter
    }

    public static let headerDate = makeDateFormatter("EEE, MMM dd")

    public static let time = makeDateFormatter("h:mm a")

    public static let separatorDate = makeDateFormatter("EEE, MMM d")

    public static let shortDate = makeDateFormatter("MMM d")

    public static let eventDetailDate = makeDateFormatter("EEEE, MMM d")

    @MainActor
    private static let fullRelativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = englishPOSIXLocale
        formatter.unitsStyle = .full
        return formatter
    }()

    @MainActor
    private static let abbreviatedRelativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = englishPOSIXLocale
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    @MainActor
    public static func relativeTimeText(
        for date: Date,
        relativeTo referenceDate: Date,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full
    ) -> String {
        let formatter = unitsStyle == .abbreviated
            ? abbreviatedRelativeDateTimeFormatter
            : fullRelativeDateTimeFormatter
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    private static let headerTimeStyle = Date.FormatStyle(
        date: .omitted,
        time: .shortened,
        locale: englishPOSIXLocale,
        calendar: Calendar(identifier: .gregorian),
        timeZone: .autoupdatingCurrent
    )

    public static func timeZoneLabel(
        for date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let abbreviation = timeZone.abbreviation(for: date), !abbreviation.isEmpty else {
            return timeZone.identifier
        }
        return abbreviation
    }

    public static func headerTimeText(
        for date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var style = headerTimeStyle
        style.timeZone = timeZone
        let time = date.formatted(style)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
        return "\(time) (\(timeZoneLabel(for: date, timeZone: timeZone)))"
    }
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

// MARK: - Unified Animation Vocabulary
//
// 4 semantic Springs mapped from Apple HIG motion principles. Pick by intent,
// not by number. Choreography animations (Confetti, Evolution, PixelPet mood
// loops) intentionally keep their own bespoke timings and bypass this table.
//
//   kiroleSnappy — micro-interactions: button press, toggle, small reveal
//   kiroleGentle — panels / modals / soft expands (default choice)
//   kiroleBouncy — success feedback, emphasis, celebratory moments
//   kiroleSmooth — page / tab transitions, large element moves
//
// Pair with `kiroleAdaptive(_:reduceMotion:)` at call sites that want to
// honor the iOS "Reduce Motion" accessibility preference.
public extension Animation {
    static let kiroleSnappy = Animation.spring(response: 0.2,  dampingFraction: 0.75)
    static let kiroleGentle = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let kiroleBouncy = Animation.spring(response: 0.3,  dampingFraction: 0.55)
    static let kiroleSmooth = Animation.spring(response: 0.55, dampingFraction: 0.88)

    // Apple-style timing curves (iOS HIG standard ease-out / decelerate).
    static let appleEaseOut    = Animation.timingCurve(0.22, 1,   0.36, 1, duration: 0.35)
    static let appleDecelerate = Animation.timingCurve(0,    0,   0.2,  1, duration: 0.3)

    /// Collapses to a near-instant linear fade when the user has enabled
    /// iOS's "Reduce Motion" accessibility setting — avoids vestibular strain
    /// from springs. Note: for `repeatForever` loops this still spins the
    /// render loop at 0.01s intervals — prefer skipping the `withAnimation`
    /// entirely at the call site for ambient/perpetual animations.
    static func kiroleAdaptive(_ full: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : full
    }
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
                        .animation(.kiroleGentle, value: configuration.isOn)
                )
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

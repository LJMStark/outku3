import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum AppHeaderLayout {
    static let horizontalPadding: CGFloat = 28
    static let tabSpacing: CGFloat = 8
    static let headerSpacing: CGFloat = 12
    static let tabOuterWidth: CGFloat = 38
    static let tabOuterHeight: CGFloat = 42
    static let tabFaceSize: CGFloat = 38
    static let tabCornerRadius: CGFloat = 11
    static let tabStrokeWidth: CGFloat = 1.5
}

public struct AppHeaderView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var appState
    @Binding var selectedTab: AppTab
    var onPetClick: (() -> Void)?

    public init(selectedTab: Binding<AppTab>, onPetClick: (() -> Void)? = nil) {
        self._selectedTab = selectedTab
        self.onPetClick = onPetClick
    }

    private var headerWidth: CGFloat? {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width
        #else
        return nil
        #endif
    }

    private var dateInfoWidth: CGFloat? {
        guard let headerWidth else { return nil }
        return max(
            160,
            headerWidth
                - AppHeaderLayout.horizontalPadding * 2
                - AppHeaderLayout.headerSpacing
                - tabGroupWidth
        )
    }

    private var tabGroupWidth: CGFloat {
        AppHeaderLayout.tabOuterWidth * 3 + AppHeaderLayout.tabSpacing * 2
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header content
            headerContent
                .background(theme.currentTheme.headerGradient)

            // Bottom decorative thick line
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 10)
        }
    }

    private var headerContent: some View {
        HStack(alignment: .top, spacing: AppHeaderLayout.headerSpacing) {
            // Date and info
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 10) {
                    Text(formattedTime)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))

                    HStack(spacing: 4) {
                        Image(systemName: appState.weather.condition.rawValue)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("\(appState.weather.highTemp)\u{00B0}/\(appState.weather.lowTemp)\u{00B0}")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            }
            .frame(width: dateInfoWidth, alignment: .leading)

            HStack(alignment: .top, spacing: AppHeaderLayout.tabSpacing) {
                TabButton(
                    icon: "house.fill",
                    label: "Home",
                    accessibilityLabel: "Home",
                    accessibilityIdentifier: "appHeader.homeTab",
                    isSelected: selectedTab == .home,
                    primaryColor: theme.colors.primary,
                    baseColor: theme.colors.primaryLight,
                    strokeColor: theme.colors.primaryDark
                ) {
                    SoundService.shared.haptic(.light)
                    withAnimation(.kiroleGentle) {
                        selectedTab = .home
                    }
                }

                PetTabButton(
                    label: "Kirole",
                    accessibilityLabel: "Pet",
                    accessibilityIdentifier: "appHeader.petTab",
                    isSelected: selectedTab == .pet,
                    primaryColor: theme.colors.primary,
                    baseColor: theme.colors.primaryLight,
                    strokeColor: theme.colors.primaryDark
                ) {
                    SoundService.shared.haptic(.light)
                    withAnimation(.kiroleGentle) {
                        selectedTab = .pet
                    }
                    onPetClick?()
                }

                TabButton(
                    icon: "gearshape.fill",
                    label: nil,
                    accessibilityLabel: "Settings",
                    accessibilityIdentifier: "appHeader.settingsTab",
                    isSelected: selectedTab == .settings,
                    primaryColor: theme.colors.primary,
                    baseColor: theme.colors.primaryLight,
                    strokeColor: theme.colors.primaryDark
                ) {
                    SoundService.shared.haptic(.light)
                    withAnimation(.kiroleGentle) {
                        selectedTab = .settings
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, AppHeaderLayout.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(width: headerWidth)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM dd"
        return formatter.string(from: appState.selectedDate)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: Date()).lowercased() + " (GMT)"
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let icon: String
    let label: String?
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let isSelected: Bool
    let primaryColor: Color
    let baseColor: Color
    let strokeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                StackedTabFrame(
                    isSelected: isSelected,
                    primaryColor: primaryColor,
                    baseColor: baseColor,
                    strokeColor: strokeColor
                ) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(strokeColor)
                }

                if let label {
                    Text(label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.kiroleIcon)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Pet Tab Button

private struct PetTabButton: View {
    @Environment(AppState.self) private var appState

    let label: String?
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let isSelected: Bool
    let primaryColor: Color
    let baseColor: Color
    let strokeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                StackedTabFrame(
                    isSelected: isSelected,
                    primaryColor: primaryColor,
                    baseColor: baseColor,
                    strokeColor: strokeColor
                ) {
                    Image(appState.userProfile.companionCharacter.heroAssetName(variant: .head), bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .offset(y: 2)
                }

                if let label {
                    Text(label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.kiroleIcon)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Stacked Tab Frame (3D double-layer)

private struct StackedTabFrame<Content: View>: View {
    let isSelected: Bool
    let primaryColor: Color
    let baseColor: Color
    let strokeColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            // Back tan layer — taller, reveals curved "shelf" at bottom
            RoundedRectangle(cornerRadius: AppHeaderLayout.tabCornerRadius)
                .fill(baseColor)
                .frame(width: AppHeaderLayout.tabOuterWidth, height: AppHeaderLayout.tabOuterHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: AppHeaderLayout.tabCornerRadius)
                        .stroke(strokeColor, lineWidth: AppHeaderLayout.tabStrokeWidth)
                )

            // Front white face — top-aligned
            RoundedRectangle(cornerRadius: AppHeaderLayout.tabCornerRadius)
                .fill(Color.white)
                .frame(width: AppHeaderLayout.tabFaceSize, height: AppHeaderLayout.tabFaceSize)
                .overlay(
                    RoundedRectangle(cornerRadius: AppHeaderLayout.tabCornerRadius)
                        .stroke(strokeColor, lineWidth: AppHeaderLayout.tabStrokeWidth)
                )
                .overlay { content }
        }
        .frame(width: AppHeaderLayout.tabOuterWidth, height: AppHeaderLayout.tabOuterHeight)
        .shadow(color: .black.opacity(0.12), radius: isSelected ? 0 : 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: AppHeaderLayout.tabCornerRadius + 2)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                .padding(-2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppHeaderLayout.tabCornerRadius + 4)
                .stroke(isSelected ? primaryColor : Color.clear, lineWidth: 2)
                .padding(-4)
        )
    }
}



// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: AppTab = .home

        var body: some View {
            VStack(spacing: 0) {
                AppHeaderView(selectedTab: $selectedTab)
                Spacer()
            }
            .background(Color(hex: "f5f1e8"))
            .environment(ThemeManager.shared)
            .environment(AppState.shared)
        }
    }

    return PreviewWrapper()
}

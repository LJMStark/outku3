import SwiftUI

public struct AppHeaderView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var appState
    @Binding var selectedTab: AppTab
    var onPetClick: (() -> Void)?

    public init(selectedTab: Binding<AppTab>, onPetClick: (() -> Void)? = nil) {
        self._selectedTab = selectedTab
        self.onPetClick = onPetClick
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
        HStack(alignment: .top) {
            // Date and info
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
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
            }

            Spacer()

            // Tab buttons
            HStack(alignment: .top, spacing: 12) {
                TabButton(
                    icon: "house.fill",
                    label: "Home",
                    isSelected: selectedTab == .home,
                    primaryColor: theme.colors.primary,
                    baseColor: theme.colors.primaryLight,
                    strokeColor: theme.colors.primaryDark
                ) {
                    withAnimation(.kiroleGentle) {
                        selectedTab = .home
                    }
                }

                PetTabButton(
                    label: "Kirole",
                    isSelected: selectedTab == .pet,
                    primaryColor: theme.colors.primary,
                    baseColor: theme.colors.primaryLight,
                    strokeColor: theme.colors.primaryDark
                ) {
                    withAnimation(.kiroleGentle) {
                        selectedTab = .pet
                    }
                    onPetClick?()
                }

                TabButton(
                    icon: "gearshape.fill",
                    label: nil,
                    isSelected: selectedTab == .settings,
                    primaryColor: theme.colors.primary,
                    baseColor: theme.colors.primaryLight,
                    strokeColor: theme.colors.primaryDark
                ) {
                    withAnimation(.kiroleGentle) {
                        selectedTab = .settings
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(strokeColor)
                }

                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.kiroleIcon)
    }
}

// MARK: - Pet Tab Button

private struct PetTabButton: View {
    let label: String?
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
                    Image("tiko_head", bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .offset(y: 2)
                }

                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.kiroleIcon)
    }
}

// MARK: - Stacked Tab Frame (3D double-layer)

private struct StackedTabFrame<Content: View>: View {
    let isSelected: Bool
    let primaryColor: Color
    let baseColor: Color
    let strokeColor: Color
    @ViewBuilder let content: Content

    private let outerWidth: CGFloat = 40
    private let outerHeight: CGFloat = 44
    private let faceSize: CGFloat = 40
    private let cornerRadius: CGFloat = 12
    private let strokeWidth: CGFloat = 1.5

    var body: some View {
        ZStack(alignment: .top) {
            // Back tan layer — taller, reveals curved "shelf" at bottom
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(baseColor)
                .frame(width: outerWidth, height: outerHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )

            // Front white face — top-aligned
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white)
                .frame(width: faceSize, height: faceSize)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )
                .overlay { content }
        }
        .frame(width: outerWidth, height: outerHeight)
        .shadow(color: .black.opacity(0.12), radius: isSelected ? 0 : 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius + 2)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                .padding(-2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius + 4)
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

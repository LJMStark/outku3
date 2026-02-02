import SwiftUI

public struct AppHeaderView: View {
    @Environment(ThemeManager.self) private var theme
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

            // Bottom decorative line
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
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
                        Text("☀️")
                        Text("85°/46°")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }

            Spacer()

            // Tab buttons
            HStack(spacing: 12) {
                TabButton(
                    icon: "house.fill",
                    isSelected: selectedTab == .home,
                    primaryColor: theme.colors.primary
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = .home
                    }
                }

                PetTabButton(
                    isSelected: selectedTab == .pet,
                    primaryColor: theme.colors.primary
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = .pet
                    }
                    onPetClick?()
                }

                TabButton(
                    icon: "gearshape.fill",
                    isSelected: selectedTab == .settings,
                    primaryColor: theme.colors.primary
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = .settings
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM dd"
        return formatter.string(from: Date())
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
    let isSelected: Bool
    let primaryColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.1), radius: isSelected ? 0 : 4, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                            .padding(-2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? primaryColor : Color.clear, lineWidth: 2)
                            .padding(-4)
                    )

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(primaryColor)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Pet Tab Button

private struct PetTabButton: View {
    let isSelected: Bool
    let primaryColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.1), radius: isSelected ? 0 : 4, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                            .padding(-2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? primaryColor : Color.clear, lineWidth: 2)
                            .padding(-4)
                    )

                Image("tiko_avatar", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
        }
    }

    return PreviewWrapper()
}

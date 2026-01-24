import SwiftUI

// MARK: - Main App View

public struct ContentView: View {
    @State private var appState = AppState.shared
    @State private var themeManager = ThemeManager.shared
    @State private var isOnboardingComplete: Bool = false

    // For demo purposes, set to false to show onboarding
    // In production, this would be persisted in UserDefaults or AppStorage
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    public var body: some View {
        ZStack {
            if hasCompletedOnboarding || isOnboardingComplete {
                mainAppView
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
                    .environment(appState)
                    .environment(themeManager)
                    .onChange(of: isOnboardingComplete) { _, newValue in
                        if newValue {
                            hasCompletedOnboarding = true
                        }
                    }
            }
        }
    }

    private var mainAppView: some View {
        ZStack {
            themeManager.colors.background
                .ignoresSafeArea()

            TabView(selection: $appState.selectedTab) {
                HomeView()
                    .tag(AppTab.home)

                PetPageView()
                    .tag(AppTab.pet)

                SettingsView()
                    .tag(AppTab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                CustomTabBar(selectedTab: $appState.selectedTab)
            }
        }
        .environment(appState)
        .environment(themeManager)
        .sheet(isPresented: $appState.isEventDetailPresented) {
            if let event = appState.selectedEvent {
                EventDetailView(event: event)
                    .environment(themeManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    public init() {}
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { selectedTab = tab }
                )
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .background {
            Capsule()
                .fill(theme.colors.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 4)
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.bottom, AppSpacing.sm)
    }
}

struct TabBarButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)

                Text(tab.rawValue)
                    .font(AppTypography.caption2)
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background {
                if isSelected {
                    Capsule()
                        .fill(theme.colors.accent.opacity(0.15))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    ContentView()
}

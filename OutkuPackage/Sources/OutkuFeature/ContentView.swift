import SwiftUI

// MARK: - Main App View

public struct ContentView: View {
    @State private var appState = AppState.shared
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = AuthManager.shared
    @State private var isOnboardingComplete: Bool = false

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    public var body: some View {
        ZStack {
            if hasCompletedOnboarding || isOnboardingComplete {
                mainAppView
            } else {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
                    .environment(appState)
                    .environment(themeManager)
                    .environment(authManager)
                    .onChange(of: isOnboardingComplete) { _, newValue in
                        if newValue {
                            hasCompletedOnboarding = true
                        }
                    }
            }
        }
        .task {
            await authManager.initialize()
        }
    }

    @ViewBuilder
    private var mainAppView: some View {
        VStack(spacing: 0) {
            // Unified Header
            AppHeaderView(selectedTab: Binding(
                get: { appState.selectedTab },
                set: { appState.selectedTab = $0 }
            ))

            // Content based on selected tab
            ZStack {
                themeManager.colors.background
                    .ignoresSafeArea(edges: .bottom)

                Group {
                    switch appState.selectedTab {
                    case .home:
                        HomeView()
                    case .pet:
                        PetPageView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
        }
        .background(themeManager.currentTheme.headerGradient.ignoresSafeArea(edges: .top))
        .environment(appState)
        .environment(themeManager)
        .environment(authManager)
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

#Preview {
    ContentView()
}

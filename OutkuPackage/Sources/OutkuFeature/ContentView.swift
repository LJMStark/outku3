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
            await configureOpenAI()
        }
    }

    private func configureOpenAI() async {
        if let apiKey = KeychainService.shared.getOpenAIAPIKey() {
            await OpenAIService.shared.configure(apiKey: apiKey)
        }
    }

    @ViewBuilder
    private var mainAppView: some View {
        ZStack(alignment: .top) {
            // Background that extends to edges
            themeManager.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Unified Header
                AppHeaderView(selectedTab: Binding(
                    get: { appState.selectedTab },
                    set: { appState.selectedTab = $0 }
                ))
                .background(themeManager.currentTheme.headerGradient.ignoresSafeArea(edges: .top))

                // Content based on selected tab
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

import SwiftUI

// MARK: - Main App View

public struct ContentView: View {
    @State private var appState = AppState.shared
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = AuthManager.shared
    @State private var isOnboardingComplete: Bool = false
    @State private var isAuthInitialized: Bool = false

    // For demo purposes, set to false to show onboarding
    // In production, this would be persisted in UserDefaults or AppStorage
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    public var body: some View {
        ZStack {
            if !isAuthInitialized {
                // Loading state while checking auth
                loadingView
            } else if !authManager.authState.isAuthenticated {
                // Not logged in - show login
                LoginView {
                    // After login, check onboarding
                }
                .environment(themeManager)
                .environment(authManager)
            } else if hasCompletedOnboarding || isOnboardingComplete {
                // Logged in and onboarded - show main app
                mainAppView
            } else {
                // Logged in but not onboarded - show onboarding
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
        .task {
            await authManager.initialize()
            isAuthInitialized = true
        }
    }

    private var loadingView: some View {
        ZStack {
            themeManager.colors.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 48))
                    .foregroundColor(themeManager.colors.accent)

                ProgressView()
                    .tint(themeManager.colors.accent)
            }
        }
    }

    private var mainAppView: some View {
        ZStack {
            themeManager.colors.background
                .ignoresSafeArea()

            // Content based on selected tab (navigation via header buttons)
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

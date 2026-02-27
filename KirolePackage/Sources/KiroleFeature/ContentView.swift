import SwiftUI

// MARK: - Main App View

public struct ContentView: View {
    @State private var appState = AppState.shared
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    public var body: some View {
        ZStack {
            if appState.isOnboardingCompleted {
                mainAppView
            } else {
                OnboardingContainerView()
                    .environment(appState)
                    .environment(themeManager)
                    .environment(authManager)
            }
        }
        .task {
            _ = FocusSessionService.shared
            await ScreenTimeFocusGuardService.shared.initialize()
            await authManager.initialize()
            appState.syncGoogleIntegrationStatusFromAuth()
            await configureOpenAI()
        }
    }

    private func configureOpenAI() async {
        // Priority: Keychain (user-entered) > App shell injected compile-time constants
        let apiKey = KeychainService.shared.getOpenAIAPIKey()
            ?? AppSecrets.openRouterAPIKey
        if let apiKey, !apiKey.isEmpty {
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
                EventDetailModal(event: event)
                    .environment(themeManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden) // hidden as we drew our own drag indicator
                    .presentationCornerRadius(24)
            }
        }
        .task {
            SyncScheduler.shared.startForegroundSync()
            if appState.isAnyAppleIntegrationConnected {
                await appState.setupAppleChangeObserver()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await SyncScheduler.shared.syncOnResume()
                    await FocusSessionService.shared.refreshProtectionStatus()
                }
                SyncScheduler.shared.startForegroundSync()
            case .background:
                SyncScheduler.shared.stopForegroundSync()
            default:
                break
            }
        }
    }

    public init() {}
}

#Preview {
    ContentView()
}

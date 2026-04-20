import SwiftUI

// MARK: - Main App View

public struct ContentView: View {
    @State private var appState = AppState.shared
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = AuthManager.shared
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldBypassOnboardingForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestSkipOnboarding")
    }

    public var body: some View {
        ZStack {
            if isOnboardingCompleted || shouldBypassOnboardingForUITests {
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
            appState.syncIntegrationStatusFromAuth()
            await configureOpenAI()
            #if DEBUG
            SimulatorBridge.shared.connect()
            #endif
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

                // All three tab views stay mounted in a ZStack so state —
                // HomeView's TimelineDataSource, scroll offset, `appeared`
                // entrance flags — survives tab switches. A switch-on-type
                // approach (or `.id(tab)`) destroys and recreates the view
                // tree, losing scroll position and replaying every staggered
                // entrance animation on every tap. Opacity + hit-testing
                // emulates the tab swap while the `.animation(...)` on the
                // parent crossfades the change under the unified motion
                // vocabulary.
                ZStack {
                    HomeView()
                        .opacity(appState.selectedTab == .home ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == .home)

                    PetPageView()
                        .opacity(appState.selectedTab == .pet ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == .pet)

                    SettingsView()
                        .opacity(appState.selectedTab == .settings ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == .settings)
                }
                .animation(
                    .kiroleAdaptive(.kiroleGentle, reduceMotion: reduceMotion),
                    value: appState.selectedTab
                )
            }
        }
        .environment(appState)
        .environment(themeManager)
        .environment(authManager)
        .sheet(isPresented: $appState.isEventDetailPresented) {
            if let event = appState.selectedEvent {
                EventDetailModal(event: event)
                    .environment(appState)
                    .environment(themeManager)
                    .environment(authManager)
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
            await appState.refreshWeather()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await appState.handleAppDidBecomeActive()
                    if appState.hasCompletedInitialHomeLoad {
                        await SyncScheduler.shared.syncOnResume()
                    }
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

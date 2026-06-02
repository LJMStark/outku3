import SwiftUI

// MARK: - Main App View

public struct ContentView: View {
    @State private var appState = AppState.shared
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = AuthManager.shared
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sceneCelebrationConfettiTrigger = 0
    @State private var sceneCelebrationDismissTask: Task<Void, Never>?

    private var shouldBypassOnboardingForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestSkipOnboarding")
    }

    public var body: some View {
        ZStack {
            if isOnboardingCompleted || shouldBypassOnboardingForUITests {
                mainAppView
            } else {
                OnboardingContainerView()
                    .injectAppEnvironment()
            }
        }
        .task {
            _ = FocusSessionService.shared
            await ScreenTimeFocusGuardService.shared.initialize()
            await authManager.initialize()
            appState.syncIntegrationStatusFromAuth()
            await configureOpenAI()
            // Ask for notification permission only after onboarding — it powers the offline
            // fallback reminder (the one channel that reaches the user when the companion
            // device is out of range). Requesting before onboarding would prompt before the
            // product is understood; UI-test runs skip onboarding via flag so they are excluded.
            if isOnboardingCompleted {
                await NotificationService.shared.requestAuthorization()
            }
            TimezoneObserver.shared.startObserving { [appState] newZone in
                appState.pendingTimezoneChangeName = newZone.localizedName(for: .generic, locale: .current) ?? newZone.identifier
            }
            #if DEBUG
            SimulatorBridge.shared.connect()
            #endif
        }
        .onChange(of: isOnboardingCompleted) { _, completed in
            // Onboarding just finished. The `.task` above already ran (with the flag still
            // false) and does NOT re-fire on the flag flip, so a brand-new user would otherwise
            // get no notification permission prompt until the next app launch — leaving the
            // offline fallback reminder dead in their first session. Request it here on the flip.
            // UI-test runs use the bypass flag (isOnboardingCompleted stays false), so they are
            // unaffected, matching the `.task` guard above.
            guard completed else { return }
            Task { await NotificationService.shared.requestAuthorization() }
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

            if let celebration = appState.pendingSceneCelebration, !appState.isFocusSettlementPresented {
                SceneUnlockBanner(
                    sceneName: DisplayScene(rawValue: celebration.sceneId)?.displayName ?? celebration.sceneId
                )
                .padding(.top, 72)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }

            if let provider = appState.remoteSyncErrors.keys.sorted().first,
               let message = appState.remoteSyncErrors[provider] {
                SyncErrorBanner(provider: provider, message: message) {
                    appState.remoteSyncErrors.removeValue(forKey: provider)
                }
                .padding(.top, 124)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(9)
            }

            if let zoneName = appState.pendingTimezoneChangeName {
                TimezoneChangeBanner(
                    zoneName: zoneName,
                    onAdjust: {
                        appState.pendingTimezoneChangeName = nil
                        Task {
                            // Refetch external data first so events re-resolve in the new
                            // time zone, then force-push so the hardware DayPack stops
                            // showing the old zone's schedule instead of waiting for the
                            // next throttled sync window.
                            await appState.syncConnectedExternalData()
                            await BLESyncCoordinator.shared.performSync(force: true)
                        }
                    },
                    onKeep: {
                        appState.pendingTimezoneChangeName = nil
                    }
                )
                .padding(.top, 176)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(8)
            }
        }
        .confetti(trigger: $sceneCelebrationConfettiTrigger)
        .animation(.kiroleSnappy, value: appState.pendingSceneCelebration)
        .animation(.kiroleSnappy, value: appState.remoteSyncErrors.count)
        .animation(.kiroleSnappy, value: appState.pendingTimezoneChangeName != nil)
        // Observable-style injection (for @Environment(Type.self) reads)
        .environment(appState)
        .environment(themeManager)
        .environment(authManager)
        .environment(FocusSessionService.shared)
        // Key-style injection (for @Environment(\.key) reads and test overrides)
        .environment(\.appState, appState)
        .environment(\.themeManager, themeManager)
        .environment(\.authManager, authManager)
        .environment(\.focusService, FocusSessionService.shared)
        .sheet(isPresented: $appState.isEventDetailPresented) {
            if let event = appState.selectedEvent {
                EventDetailModal(event: event)
                    .injectAppEnvironment()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
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
        .onChange(of: appState.pendingSceneCelebration) { _, celebration in
            guard celebration != nil else { return }
            sceneCelebrationConfettiTrigger += 1
            sceneCelebrationDismissTask?.cancel()
            sceneCelebrationDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                appState.pendingSceneCelebration = nil
            }
        }
    }

    public init() {}
}

// MARK: - Scene Unlock Banner

private struct SceneUnlockBanner: View {
    @Environment(ThemeManager.self) private var theme
    let sceneName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("New scene unlocked · apply in Settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
                Text(sceneName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(theme.colors.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unlocked \(sceneName)")
        .accessibilityIdentifier("app.sceneUnlockBanner")
    }
}

// MARK: - Timezone Change Banner

private struct TimezoneChangeBanner: View {
    @Environment(ThemeManager.self) private var theme
    let zoneName: String
    let onAdjust: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Looks like you've moved · \(zoneName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
                HStack(spacing: 8) {
                    Button("Fix my times", action: onAdjust)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.colors.accent)
                        .accessibilityIdentifier("timezone.updateButton")
                    Text("·")
                        .foregroundStyle(theme.colors.secondaryText)
                    Button("Not now", action: onKeep)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.secondaryText)
                        .accessibilityIdentifier("timezone.keepButton")
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(theme.colors.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Looks like you've moved to \(zoneName). Want me to fix your times?")
        .accessibilityIdentifier("app.timezoneChangeBanner")
    }
}

// MARK: - Sync Error Banner

private struct SyncErrorBanner: View {
    @Environment(ThemeManager.self) private var theme
    let provider: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(provider) sync failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
                Text("Tap to dismiss")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(theme.colors.cardBackground)
                .shadow(color: .red.opacity(0.12), radius: 8, y: 4)
        )
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider) sync failed. Tap to dismiss.")
        .accessibilityIdentifier("app.syncErrorBanner")
    }
}

#Preview {
    ContentView()
}

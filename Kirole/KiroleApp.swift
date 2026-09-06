import SwiftUI
import KiroleFeature
import UIKit

@MainActor
private final class KiroleAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // SwiftUI keeps ownership of WindowGroup and its window; only add URL callbacks.
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = KiroleSceneDelegate.self
        }
        return configuration
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        KiroleOAuthURLRouter.handle(
            url,
            sourceApplication: options[.sourceApplication] as? String
        )
    }
}

@MainActor
private final class KiroleSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        route(connectionOptions.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        route(URLContexts)
    }

    private func route(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            KiroleOAuthURLRouter.handle(
                context.url,
                sourceApplication: context.options.sourceApplication
            )
        }
    }
}

@MainActor
private enum KiroleOAuthURLRouter {
    @discardableResult
    static func handle(_ url: URL, sourceApplication: String?) -> Bool {
        // Broker responses arrive through the scene lifecycle in SwiftUI. Forward the real
        // source application so MSAL can validate it, before trying the other OAuth providers.
        // Each system callback routes here once; WindowGroup must not also consume the URL.
        if MicrosoftAuthService.handleRedirectURL(
            url,
            sourceApplication: sourceApplication
        ) {
            return true
        }
        return AuthManager.shared.handleURL(url)
    }
}

@main
struct KiroleApp: App {
    @UIApplicationDelegateAdaptor(KiroleAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            try LocalStorage.resetForRapidDevelopmentIfNeeded()
        } catch {
            print("Failed to reset local development storage: \(error.localizedDescription)")
        }

        AppSecrets.configure(
            supabaseURL: BuildSecrets.supabaseURL,
            supabaseAnonKey: BuildSecrets.supabaseAnonKey,
            openRouterAPIKey: BuildSecrets.openRouterAPIKey,
            bleSharedSecret: BuildSecrets.bleSharedSecret,
            deepFocusFeatureEnabled: BuildSecrets.deepFocusFeatureEnabled,
            microsoftClientId: BuildSecrets.microsoftClientId,
            microsoftOAuthEnabled: BuildSecrets.microsoftOAuthEnabled,
            openAIBaseURL: BuildSecrets.openAIBaseURL,
            chatModelID: BuildSecrets.chatModelID,
            fallbackAPIKey: BuildSecrets.fallbackAPIKey
        )
        BLEBackgroundSyncScheduler.shared.register()
        InternalBuildBoundary.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .internalToolsViews(InternalBuildBoundary.toolsViews)
                .task {
                    BLEBackgroundSyncScheduler.shared.schedule()
                    await NotificationService.shared.refreshAuthorizationStatus()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active || newPhase == .background {
                BLEBackgroundSyncScheduler.shared.schedule()
            }
        }
    }
}

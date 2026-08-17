import SwiftUI
import KiroleFeature
import UIKit

@MainActor
private final class KiroleAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if MicrosoftAuthService.handleRedirectURL(
            url,
            sourceApplication: options[.sourceApplication] as? String
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
            notionClientId: BuildSecrets.notionClientId,
            notionOAuthEnabled: BuildSecrets.notionOAuthEnabled,
            taskadeClientId: BuildSecrets.taskadeClientId,
            taskadeOAuthEnabled: BuildSecrets.taskadeOAuthEnabled,
            microsoftClientId: BuildSecrets.microsoftClientId,
            microsoftOAuthEnabled: BuildSecrets.microsoftOAuthEnabled,
            todoistClientId: BuildSecrets.todoistClientId,
            todoistOAuthEnabled: BuildSecrets.todoistOAuthEnabled,
            tickTickOAuthEnabled: BuildSecrets.tickTickOAuthEnabled,
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

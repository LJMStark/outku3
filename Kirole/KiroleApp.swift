import SwiftUI
import KiroleFeature

@main
struct KiroleApp: App {
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
            taskadeClientId: BuildSecrets.taskadeClientId,
            openAIBaseURL: BuildSecrets.openAIBaseURL,
            chatModelID: BuildSecrets.chatModelID,
            fallbackAPIKey: BuildSecrets.fallbackAPIKey
        )
        BLEBackgroundSyncScheduler.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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

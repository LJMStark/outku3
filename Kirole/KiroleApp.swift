import SwiftUI
import KiroleFeature

@main
struct KiroleApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppSecrets.configure(
            supabaseURL: BuildSecrets.supabaseURL,
            supabaseAnonKey: BuildSecrets.supabaseAnonKey,
            openRouterAPIKey: BuildSecrets.openRouterAPIKey,
            bleSharedSecret: BuildSecrets.bleSharedSecret,
            deepFocusFeatureEnabled: BuildSecrets.deepFocusFeatureEnabled,
            notionClientId: BuildSecrets.notionClientId,
            notionClientSecret: BuildSecrets.notionClientSecret,
            taskadeClientId: BuildSecrets.taskadeClientId,
            taskadeClientSecret: BuildSecrets.taskadeClientSecret
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

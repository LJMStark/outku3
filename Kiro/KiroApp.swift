import SwiftUI
import KiroFeature

@main
struct KiroApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BLEBackgroundSyncScheduler.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    BLEBackgroundSyncScheduler.shared.schedule()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active || newPhase == .background {
                BLEBackgroundSyncScheduler.shared.schedule()
            }
        }
    }
}

import Testing
@testable import KiroleFeature

@Suite("Home manual refresh")
struct HomeManualRefreshTests {
    @Test("pull to refresh forces a manual BLE sync")
    @MainActor
    func pullToRefreshUsesManualTrigger() async {
        var steps: [String] = []
        var receivedForce: Bool?
        var receivedTrigger: BLESyncTrigger?

        await HomeManualRefreshFlow.perform(
            cancelPendingBLESync: {
                steps.append("cancel")
            },
            syncExternalData: { scheduleBLESync in
                steps.append("external:\(scheduleBLESync)")
            },
            refreshDialogue: { force in
                steps.append("dialogue:\(force)")
            },
            switchToPetDialogue: {
                steps.append("presentation")
            },
            syncBLE: { force, trigger in
                steps.append("ble")
                receivedForce = force
                receivedTrigger = trigger
            }
        )

        #expect(steps == ["cancel", "external:false", "cancel", "dialogue:true", "presentation", "ble"])
        #expect(receivedForce == true)
        #expect(receivedTrigger == .manual)
    }
}

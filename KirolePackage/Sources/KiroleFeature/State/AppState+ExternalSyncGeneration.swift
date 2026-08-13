import Foundation

extension AppState {
    func externalSyncGeneration(for target: ExternalSyncTarget) -> UInt64 {
        externalSyncGenerations[target, default: 0]
    }

    func canCommitExternalSync(
        _ target: ExternalSyncTarget,
        generation: UInt64
    ) -> Bool {
        externalSyncGeneration(for: target) == generation
    }

    /// Claims the current provider generation's sync slot. An older generation never blocks a
    /// replacement sync after disconnect/reconnect, while duplicate work within one generation is
    /// still coalesced.
    func beginExternalSync(_ target: ExternalSyncTarget) -> UInt64? {
        let generation = externalSyncGeneration(for: target)
        guard activeExternalSyncGenerations[target] != generation else { return nil }
        activeExternalSyncGenerations[target] = generation
        return generation
    }

    func finishExternalSync(_ target: ExternalSyncTarget, generation: UInt64) {
        guard activeExternalSyncGenerations[target] == generation else { return }
        activeExternalSyncGenerations.removeValue(forKey: target)
    }

    func invalidateExternalSyncResults(for targets: Set<ExternalSyncTarget>) {
        for target in targets {
            externalSyncGenerations[target, default: 0] &+= 1
        }
    }

    func invalidateAllExternalSyncResults() {
        invalidateExternalSyncResults(for: Set(ExternalSyncTarget.allCases))
    }

    func invalidateExternalSyncResults(for type: IntegrationType) {
        guard let target = ExternalSyncTarget(integrationType: type) else { return }
        invalidateExternalSyncResults(for: [target])
    }
}

private extension ExternalSyncTarget {
    init?(integrationType: IntegrationType) {
        switch integrationType {
        case .googleCalendar, .googleTasks:
            self = .google
        case .appleCalendar, .appleReminders, .caldav, .icalWebcal:
            self = .apple
        case .notion:
            self = .notion
        case .taskade:
            self = .taskade
        case .outlookCalendar, .microsoftToDo:
            self = .microsoft
        case .todoist:
            self = .todoist
        case .tickTick:
            self = .tickTick
        }
    }
}

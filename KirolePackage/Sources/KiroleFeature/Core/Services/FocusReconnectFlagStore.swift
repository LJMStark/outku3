import Foundation

@MainActor
final class FocusReconnectFlags {
    var isFocusStatusPushFrozen = false
    var lastAppliedFocusRevision: UInt32 = 0
    var suppressVisibleFocusStart = false
    var lastResolveID: UInt32 = 0
    var lastResolveSessionId = FocusSessionId.idle
}

@MainActor
enum FocusReconnectFlagStore {
    private static var byService: [ObjectIdentifier: FocusReconnectFlags] = [:]

    static func flags(for service: FocusSessionService) -> FocusReconnectFlags {
        let id = ObjectIdentifier(service)
        if let existing = byService[id] { return existing }
        let created = FocusReconnectFlags()
        byService[id] = created
        return created
    }
}

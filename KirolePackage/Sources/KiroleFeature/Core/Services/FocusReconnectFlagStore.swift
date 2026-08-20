import Foundation

struct FocusStatusFreezeLease: Hashable, Sendable {
    fileprivate let id: UUID

    fileprivate init(id: UUID = UUID()) {
        self.id = id
    }
}

@MainActor
final class FocusReconnectFlags {
    private var focusStatusFreezeLeases: Set<FocusStatusFreezeLease> = []
    private var legacyFocusStatusFreezeLease: FocusStatusFreezeLease?
    private(set) var focusStatusFreezeEpoch: UInt64 = 0
    var lastAppliedFocusRevision: UInt32 = 0
    var suppressVisibleFocusStart = false
    var lastResolveID: UInt32 = 0
    var lastResolveSessionId = FocusSessionId.idle
    var lastResolveCommand: OfflineFocusResolve?
    var pendingReconnectAction: FocusReconnectAction?

    var isFocusStatusPushFrozen: Bool {
        !focusStatusFreezeLeases.isEmpty
    }

    func acquireFocusStatusFreeze() -> FocusStatusFreezeLease {
        let lease = FocusStatusFreezeLease()
        focusStatusFreezeLeases.insert(lease)
        focusStatusFreezeEpoch &+= 1
        return lease
    }

    func releaseFocusStatusFreeze(_ lease: FocusStatusFreezeLease) {
        focusStatusFreezeLeases.remove(lease)
    }

    func setLegacyFocusStatusFreeze(_ frozen: Bool) {
        if frozen {
            guard legacyFocusStatusFreezeLease == nil else { return }
            let lease = acquireFocusStatusFreeze()
            legacyFocusStatusFreezeLease = lease
            return
        }
        guard let lease = legacyFocusStatusFreezeLease else { return }
        legacyFocusStatusFreezeLease = nil
        releaseFocusStatusFreeze(lease)
    }
}

@MainActor
enum FocusReconnectFlagStore {
    private struct Entry {
        weak var service: FocusSessionService?
        let flags: FocusReconnectFlags
    }

    private static var byService: [ObjectIdentifier: Entry] = [:]

    static func flags(for service: FocusSessionService) -> FocusReconnectFlags {
        let id = ObjectIdentifier(service)
        if let existing = byService[id], existing.service === service {
            return existing.flags
        }
        byService = byService.filter { $0.value.service != nil }
        let created = FocusReconnectFlags()
        byService[id] = Entry(service: service, flags: created)
        return created
    }
}

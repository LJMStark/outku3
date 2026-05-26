import Foundation

// MARK: - Companion Selection

/// Branching shape for "which companion is active right now".
/// `UserProfile.currentSelection` is the only public surface that surfaces this — most call
/// sites can keep reading `userProfile.companionCharacter` and stay oblivious to .custom.
public enum CompanionSelection: Sendable, Equatable, Hashable {
    case builtIn(CompanionCharacter)
    case custom(UUID)
}

public extension CompanionSelection {
    /// Resolve to a concrete CustomCompanion when this selection is `.custom`.
    /// Returns nil if the id no longer exists (e.g. the user deleted the custom companion
    /// since the profile was written) — callers should fall back to the built-in character.
    func resolveCustom(in companions: [CustomCompanion]) -> CustomCompanion? {
        if case .custom(let id) = self {
            return companions.first { $0.id == id }
        }
        return nil
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

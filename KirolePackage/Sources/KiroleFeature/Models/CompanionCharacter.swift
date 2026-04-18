import Foundation

public enum CompanionCharacter: String, CaseIterable, Sendable, Codable {
    case nook = "nook"
    case silas = "silas"
    case nova = "nova"

    public var displayName: String {
        switch self {
        case .nook: return "Nook"
        case .silas: return "Silas"
        case .nova: return "Nova"
        }
    }

    /// The prompt style bound to this character.
    /// Character is the single source of truth; style is always derived.
    public var resolvedStyle: CompanionStyle {
        switch self {
        case .nook:
            return .companion
        case .silas:
            return .slacker
        case .nova:
            return .challenger
        }
    }

    public var styleDescription: String {
        resolvedStyle.description
    }
}

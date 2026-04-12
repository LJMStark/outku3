import Foundation

public enum IntimacyStage: String, CaseIterable, Sendable, Codable, Comparable {
    case acquaintance = "acquaintance"
    case familiar = "familiar"
    case closeFriend = "closeFriend"

    public var displayName: String {
        switch self {
        case .acquaintance: return "Acquaintance"
        case .familiar: return "Familiar"
        case .closeFriend: return "Close Friend"
        }
    }
    
    public static func < (lhs: IntimacyStage, rhs: IntimacyStage) -> Bool {
        let order: [IntimacyStage] = [.acquaintance, .familiar, .closeFriend]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }

    public static func from(bindingDays: Int) -> IntimacyStage {
        switch bindingDays {
        case 16...:
            return .closeFriend
        case 6...:
            return .familiar
        default:
            return .acquaintance
        }
    }
}

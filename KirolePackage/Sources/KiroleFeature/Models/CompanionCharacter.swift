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

    public var defaultCompanionStyle: CompanionStyle {
        switch self {
        case .nook:
            return .companion
        case .silas:
            return .slacker
        case .nova:
            return .challenger
        }
    }

    public static func fromProductStyle(_ style: CompanionStyle) -> CompanionCharacter? {
        switch style {
        case .companion:
            return .nook
        case .slacker:
            return .silas
        case .challenger:
            return .nova
        default:
            return nil
        }
    }
}

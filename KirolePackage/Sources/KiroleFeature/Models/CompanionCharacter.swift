import Foundation

public enum CompanionCharacter: String, CaseIterable, Sendable, Codable {
    case joy = "joy"
    case silas = "silas"
    case nova = "nova"

    public var displayName: String {
        switch self {
        case .joy: return "Joy"
        case .silas: return "Silas"
        case .nova: return "Nova"
        }
    }

    /// The prompt style bound to this character.
    /// Character is the single source of truth; style is always derived.
    public var resolvedStyle: CompanionStyle {
        switch self {
        case .joy:
            return .joy
        case .silas:
            return .silas
        case .nova:
            return .nova
        }
    }

    public var styleDescription: String {
        resolvedStyle.description
    }

    public enum HeroAssetVariant: Sendable {
        case main
        case head
        /// Full-bleed scene illustration used on the Pet page header.
        /// Only Joy currently has a dedicated scene asset; other characters fall back to `.main`.
        case scene
    }

    /// Returns the asset name to load via `Image(name, bundle: .module)`.
    /// Maps to per-character `<rawValue>-main` / `<rawValue>-head` / `<rawValue>-scene` images
    /// shipped under `Resources/Media.xcassets/` (e.g. `joy-main`, `joy-scene`).
    public func heroAssetName(variant: HeroAssetVariant) -> String {
        switch variant {
        case .main: return "\(rawValue)-main"
        case .head: return "\(rawValue)-head"
        case .scene:
            return "\(rawValue)-scene"
        }
    }
}

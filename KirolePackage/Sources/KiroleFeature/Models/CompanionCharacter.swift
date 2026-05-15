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
        /// Reading/idle pose used in Timeline haiku section and Focus mode.
        case reading
        /// Sunrise marker icon used in the Timeline header row.
        /// Joy and Nova currently reuse the legacy tiko_sunrise art as placeholder.
        case sunrise
        /// Sunset marker icon used in the Timeline footer row.
        /// Joy and Nova currently reuse the legacy tiko_sunset art as placeholder.
        case sunset
        /// Profile card pose used exclusively in PetStatusView.
        case profile
    }

    /// Returns the asset name to load via `Image(name, bundle: .module)`.
    /// Maps to per-character `<rawValue>-main` / `<rawValue>-head` / `<rawValue>-scene` images
    /// shipped under `Resources/Media.xcassets/` (e.g. `joy-main`, `joy-scene`).
    public func heroAssetName(variant: HeroAssetVariant) -> String {
        switch variant {
        case .main: return "\(rawValue)-main"
        case .head: return "\(rawValue)-head"
        case .scene: return "\(rawValue)-scene"
        case .reading: return "\(rawValue)-reading"
        case .sunrise: return "\(rawValue)-sunrise"
        case .sunset: return "\(rawValue)-sunset"
        case .profile:
            switch self {
            case .silas: return "silas-profile"
            default: return "\(rawValue)-main"
            }
        }
    }
}

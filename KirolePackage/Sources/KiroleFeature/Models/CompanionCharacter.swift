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
        /// Full-bleed companion illustration used on the Pet page header.
        /// The explicit name keeps Pet page artwork distinct from hardware `DisplayScene` previews.
        case petScene
        /// Reading/idle pose used in Timeline haiku section and Focus mode.
        case reading
        /// Character-specific sunrise marker icon used in the Timeline header row.
        case sunrise
        /// Character-specific sunset marker icon used in the Timeline footer row.
        case sunset
        /// Profile card pose used exclusively in PetStatusView.
        /// Always `<rawValue>-profile` (Joy currently ships the same art as `joy-main`).
        case profile
    }

    /// Returns the asset name to load via `Image(name, bundle: .module)`.
    /// Maps to per-character `<rawValue>-main` / `<rawValue>-head` /
    /// `<rawValue>-pet-scene` images shipped under `Resources/Media.xcassets/`.
    public func heroAssetName(variant: HeroAssetVariant) -> String {
        switch variant {
        case .main: return "\(rawValue)-main"
        case .head: return "\(rawValue)-head"
        case .petScene: return "\(rawValue)-pet-scene"
        case .reading: return "\(rawValue)-reading"
        case .sunrise: return "\(rawValue)-sunrise"
        case .sunset: return "\(rawValue)-sunset"
        case .profile: return "\(rawValue)-profile"
        }
    }
}

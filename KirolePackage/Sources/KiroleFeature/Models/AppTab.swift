import Foundation

public enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case pet = "Tiko"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .pet: return "pawprint.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

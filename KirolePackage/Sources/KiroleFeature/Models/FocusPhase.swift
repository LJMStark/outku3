import Foundation

public enum FocusPhase: String, Sendable, Codable, Equatable {
    case idle = "idle"
    /// 0-5 mins
    case warmup = "warmup"
    /// 6-15 mins
    case building = "building"
    /// 16-30 mins
    case deep = "deep"
    
    public var displayString: String {
        switch self {
        case .idle: return "Idle"
        case .warmup: return "Warmup Phase (0-5m)"
        case .building: return "Building Phase (6-15m)"
        case .deep: return "Deep Focus (16-30m)"
        }
    }

    public static func from(elapsedMinutes: Int) -> FocusPhase {
        switch elapsedMinutes {
        case ..<1:
            return .idle
        case ...5:
            return .warmup
        case ...15:
            return .building
        default:
            return .deep
        }
    }
}

import Foundation

public struct Haiku: Identifiable, Sendable, Codable {
    public let id: UUID
    public var lines: [String]

    public init(id: UUID = UUID(), lines: [String]) {
        self.id = id
        self.lines = lines
    }

    public static var placeholder: Haiku {
        Haiku(lines: [
            "Morning light arrives",
            "Tasks await with gentle hope",
            "One step at a time"
        ])
    }
}

import Foundation

// MARK: - Micro Action

/// AI 分解的微行动步骤
public struct MicroAction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let what: String
    public let when: String?
    public let why: String?
    public let estimatedMinutes: Int?

    public init(
        id: UUID = UUID(),
        what: String,
        when: String? = nil,
        why: String? = nil,
        estimatedMinutes: Int? = nil
    ) {
        self.id = id
        self.what = String(what.prefix(40))
        self.when = when
        self.why = why.map { String($0.prefix(60)) }
        self.estimatedMinutes = estimatedMinutes
    }
}

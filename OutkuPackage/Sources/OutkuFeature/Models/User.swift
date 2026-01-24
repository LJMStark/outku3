import Foundation

// MARK: - User Model

public struct User: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var email: String?
    public var displayName: String?
    public var avatarURL: URL?
    public var authProvider: AuthProvider
    public var createdAt: Date
    public var lastLoginAt: Date

    public init(
        id: String,
        email: String? = nil,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        authProvider: AuthProvider,
        createdAt: Date = Date(),
        lastLoginAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.authProvider = authProvider
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
    }
}

// MARK: - Auth Provider

public enum AuthProvider: String, Codable, Sendable {
    case apple = "apple"
    case google = "google"
}

// MARK: - Auth State

public enum AuthState: Sendable, Equatable {
    case unauthenticated
    case authenticating
    case authenticated(User)
    case error(String)

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    public var user: User? {
        if case .authenticated(let user) = self { return user }
        return nil
    }
}

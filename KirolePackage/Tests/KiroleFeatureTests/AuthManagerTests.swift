import Testing
import Foundation
@testable import KiroleFeature

// MARK: - AuthManager Tests

@Suite("AuthManager Tests")
struct AuthManagerTests {

    // MARK: - AuthState Tests

    @Test("AuthState isAuthenticated property")
    func authStateIsAuthenticated() {
        let user = User(id: "test-user", authProvider: .apple)

        #expect(AuthState.unauthenticated.isAuthenticated == false)
        #expect(AuthState.authenticating.isAuthenticated == false)
        #expect(AuthState.authenticated(user).isAuthenticated == true)
        #expect(AuthState.error("error").isAuthenticated == false)
    }

    @Test("AuthState user property")
    func authStateUser() {
        let user = User(id: "test-user", email: "test@example.com", authProvider: .apple)

        #expect(AuthState.unauthenticated.user == nil)
        #expect(AuthState.authenticated(user).user?.id == "test-user")
    }

    @Test("AuthState transitions")
    func authStateTransitions() {
        let user = User(id: "user-1", authProvider: .apple)

        // unauthenticated -> authenticating -> authenticated
        var state: AuthState = .unauthenticated
        state = .authenticating
        #expect(state == .authenticating)

        state = .authenticated(user)
        #expect(state.isAuthenticated == true)

        // authenticated -> unauthenticated (sign out)
        state = .unauthenticated
        #expect(state == .unauthenticated)

        // authenticating -> error
        state = .error("Failed")
        #expect(state == .error("Failed"))
    }

    // MARK: - User Model Tests

    @Test("User initialization and equality")
    func userInitAndEquality() {
        let now = Date()
        let user1 = User(id: "user-123", authProvider: .google, createdAt: now, lastLoginAt: now)
        let user2 = User(id: "user-123", authProvider: .google, createdAt: now, lastLoginAt: now)
        let user3 = User(id: "different", authProvider: .apple, createdAt: now, lastLoginAt: now)

        #expect(user1.id == "user-123")
        #expect(user1.authProvider == .google)
        #expect(user1 == user2)
        #expect(user1 != user3)
    }

    @Test("User Codable")
    func userCodable() throws {
        let user = User(id: "codable-user", email: "test@example.com", authProvider: .google)

        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(User.self, from: data)

        #expect(decoded.id == user.id)
        #expect(decoded.email == user.email)
    }

    @Test("Canonical user prefers Supabase UUID")
    func canonicalUserPrefersSupabaseID() {
        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
        let supabaseUser = SupabaseUser(
            id: "supabase-uuid",
            email: "supabase@example.com",
            createdAt: createdAt
        )

        let user = AuthManager.makeCanonicalUser(
            providerUserID: "google-sub",
            email: "google@example.com",
            displayName: "Kirole",
            avatarURL: nil,
            authProvider: .google,
            supabaseUser: supabaseUser
        )

        #expect(user.id == "supabase-uuid")
        #expect(user.email == "supabase@example.com")
        #expect(user.displayName == "Kirole")
        #expect(user.authProvider == .google)
        #expect(user.createdAt == createdAt)
    }

    @Test("Canonical user falls back to provider identity when Supabase user is missing")
    func canonicalUserFallsBackWithoutSupabaseUser() {
        let user = AuthManager.makeCanonicalUser(
            providerUserID: "apple-user-id",
            email: "apple@example.com",
            displayName: "Apple User",
            avatarURL: nil,
            authProvider: .apple,
            supabaseUser: nil
        )

        #expect(user.id == "apple-user-id")
        #expect(user.email == "apple@example.com")
        #expect(user.displayName == "Apple User")
        #expect(user.authProvider == .apple)
    }

    // MARK: - AuthManager Sign Out

    @Test("Sign out clears all state")
    @MainActor
    func signOutClearsState() async {
        let manager = AuthManager.shared

        await manager.signOut()

        #expect(manager.authState == .unauthenticated)
        #expect(manager.currentUser == nil)
        #expect(manager.isGoogleConnected == false)
    }
}

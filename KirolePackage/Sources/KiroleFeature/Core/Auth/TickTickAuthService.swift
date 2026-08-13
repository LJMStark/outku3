import AuthenticationServices
import Foundation
@preconcurrency import KeychainAccess
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
struct TickTickOAuthConfiguration: Sendable, Equatable {
    let backendEndpoint: URL
    let returnURI: URL
    let region: TickTickRegion
    let backendAPIKey: String

    init(
        backendEndpoint: URL,
        returnURI: URL,
        region: TickTickRegion,
        backendAPIKey: String
    ) throws {
        guard backendEndpoint.scheme == "https",
              backendEndpoint.host != nil,
              returnURI.scheme == "https",
              returnURI.host != nil,
              !backendAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TickTickAuthError.invalidConfiguration
        }
        self.backendEndpoint = backendEndpoint
        self.returnURI = returnURI
        self.region = region
        self.backendAPIKey = backendAPIKey
    }
    var callbackHostAndPath: (host: String, path: String)? {
        guard let host = returnURI.host else { return nil }
        return (host, returnURI.path)
    }
}

enum TickTickBackendAction: Sendable, Equatable {
    case start
    case claim(attemptID: String, claimSecret: String)
    case acknowledge(attemptID: String, claimSecret: String, deliveryID: String)
    case cancel(attemptID: String, claimSecret: String)
    case disconnect(connectionID: String)
}

enum TickTickBackendRequestBuilder {
    static func request(
        configuration: TickTickOAuthConfiguration,
        action: TickTickBackendAction,
        userAccessToken: String
    ) throws -> URLRequest {
        guard !userAccessToken.isEmpty else { throw TickTickAuthError.kiroleSignInRequired }

        let payload: Payload
        switch action {
        case .start:
            payload = Payload(action: "start", region: configuration.region.rawValue)
        case .claim(let attemptID, let claimSecret):
            payload = Payload(
                action: "claim",
                attemptID: attemptID,
                claimSecret: claimSecret
            )
        case .acknowledge(let attemptID, let claimSecret, let deliveryID):
            payload = Payload(
                action: "ack",
                attemptID: attemptID,
                claimSecret: claimSecret,
                deliveryID: deliveryID
            )
        case .cancel(let attemptID, let claimSecret):
            payload = Payload(
                action: "cancel",
                attemptID: attemptID,
                claimSecret: claimSecret
            )
        case .disconnect(let connectionID):
            payload = Payload(action: "disconnect", connectionID: connectionID)
        }

        var request = URLRequest(url: configuration.backendEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(userAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.backendAPIKey, forHTTPHeaderField: "apikey")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private struct Payload: Encodable {
        let action: String
        var region: String?
        var attemptID: String?
        var claimSecret: String?
        var deliveryID: String?
        var connectionID: String?

        enum CodingKeys: String, CodingKey {
            case action, region
            case attemptID = "attempt_id"
            case claimSecret = "claim_secret"
            case deliveryID = "delivery_id"
            case connectionID = "connection_id"
        }
    }
}

public struct TickTickTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date?
    public let scope: String?
    /// Kirole connection namespace. TickTick does not publish a profile endpoint.
    public let accountID: String
    public let region: TickTickRegion
    public let ownerUserID: String

    public init(
        accessToken: String,
        expiresAt: Date?,
        scope: String?,
        accountID: String,
        region: TickTickRegion,
        ownerUserID: String
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.accountID = accountID
        self.region = region
        self.ownerUserID = ownerUserID
    }
}

struct TickTickTokenDelivery: Codable, Sendable, Equatable {
    let deliveryID: String
    let tokens: TickTickTokenSet
}

struct TickTickPendingAuthorization: Codable, Sendable, Equatable {
    let attemptID: String
    let claimSecret: String
    let region: TickTickRegion
    let ownerUserID: String
    let expiresAt: Date
    var delivery: TickTickTokenDelivery?
}

struct TickTickAuthorizationStart: Sendable, Equatable {
    let authorizationURL: URL
    let pending: TickTickPendingAuthorization
}

protocol TickTickTokenStoring: Sendable {
    func load() async throws -> TickTickTokenSet?
    func save(_ tokens: TickTickTokenSet) async throws
    func clear() async throws
}

protocol TickTickPendingAuthorizationStoring: Sendable {
    func load() async throws -> TickTickPendingAuthorization?
    func save(_ pending: TickTickPendingAuthorization) async throws
    func clear() async throws
}

actor TickTickKeychainTokenStore: TickTickTokenStoring {
    private let keychain: Keychain
    private let key: String

    init(region: TickTickRegion, service: String = "com.kirole.app") {
        keychain = Keychain(service: service).accessibility(.afterFirstUnlockThisDeviceOnly)
        key = "ticktick_token_set_\(region.rawValue)"
    }

    func load() throws -> TickTickTokenSet? {
        guard let data = try keychain.getData(key) else { return nil }
        return try JSONDecoder().decode(TickTickTokenSet.self, from: data)
    }

    func save(_ tokens: TickTickTokenSet) throws {
        try keychain.set(JSONEncoder().encode(tokens), key: key)
    }

    func clear() throws {
        try keychain.remove(key)
    }
}

actor TickTickPendingAuthorizationStore: TickTickPendingAuthorizationStoring {
    private let keychain: Keychain
    private let key: String

    init(region: TickTickRegion, service: String = "com.kirole.app") {
        keychain = Keychain(service: service).accessibility(.afterFirstUnlockThisDeviceOnly)
        key = "ticktick_pending_oauth_\(region.rawValue)"
    }

    func load() throws -> TickTickPendingAuthorization? {
        guard let data = try keychain.getData(key) else { return nil }
        return try JSONDecoder().decode(TickTickPendingAuthorization.self, from: data)
    }

    func save(_ pending: TickTickPendingAuthorization) throws {
        try keychain.set(JSONEncoder().encode(pending), key: key)
    }

    func clear() throws {
        try keychain.remove(key)
    }
}

protocol TickTickOAuthBackendServing: Sendable {
    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart
    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery
    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws
    func cancel(attemptID: String, claimSecret: String) async throws
    func disconnect(connectionID: String) async throws
}

private final class TickTickNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum TickTickOAuthTransport {
    static let session = URLSession(
        configuration: .ephemeral,
        delegate: TickTickNoRedirectDelegate(),
        delegateQueue: nil
    )
}

actor TickTickOAuthBackend: TickTickOAuthBackendServing {
    private struct StartResponse: Decodable {
        let attemptID: String
        let claimSecret: String
        let authorizationURL: URL
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case attemptID = "attempt_id"
            case claimSecret = "claim_secret"
            case authorizationURL = "authorization_url"
            case expiresAt = "expires_at"
        }
    }

    private struct ClaimResponse: Decodable {
        let deliveryID: String
        let accessToken: String
        let connectionID: String
        let region: TickTickRegion
        let scope: String?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case deliveryID = "delivery_id"
            case accessToken = "access_token"
            case connectionID = "connection_id"
            case region, scope
            case expiresAt = "expires_at"
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String?
    }

    private let configuration: TickTickOAuthConfiguration
    private let session: URLSession
    private let userAccessToken: @Sendable () async throws -> String

    init(
        configuration: TickTickOAuthConfiguration,
        session: URLSession = TickTickOAuthTransport.session,
        userAccessToken: @escaping @Sendable () async throws -> String
    ) {
        self.configuration = configuration
        self.session = session
        self.userAccessToken = userAccessToken
    }

    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart {
        guard region == configuration.region else { throw TickTickAuthError.regionMismatch }
        let data = try await perform(.start, success: 200)
        let payload: StartResponse = try decode(data)
        guard payload.authorizationURL.scheme == "https",
              payload.authorizationURL.host == configuration.region.authorizationEndpoint.host,
              let expiresAt = Self.parseDate(payload.expiresAt) else {
            throw TickTickAuthError.invalidResponse
        }
        return TickTickAuthorizationStart(
            authorizationURL: payload.authorizationURL,
            pending: TickTickPendingAuthorization(
                attemptID: payload.attemptID,
                claimSecret: payload.claimSecret,
                region: configuration.region,
                ownerUserID: "",
                expiresAt: expiresAt,
                delivery: nil
            )
        )
    }

    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery {
        let data = try await perform(
            .claim(attemptID: attemptID, claimSecret: claimSecret),
            success: 200
        )
        let payload: ClaimResponse = try decode(data)
        guard payload.region == configuration.region else { throw TickTickAuthError.regionMismatch }
        return TickTickTokenDelivery(
            deliveryID: payload.deliveryID,
            tokens: TickTickTokenSet(
                accessToken: payload.accessToken,
                expiresAt: payload.expiresAt.flatMap(Self.parseDate),
                scope: payload.scope,
                accountID: payload.connectionID,
                region: payload.region,
                ownerUserID: ""
            )
        )
    }

    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws {
        _ = try await perform(
            .acknowledge(
                attemptID: attemptID,
                claimSecret: claimSecret,
                deliveryID: deliveryID
            ),
            success: 204
        )
    }

    func disconnect(connectionID: String) async throws {
        _ = try await perform(.disconnect(connectionID: connectionID), success: 204)
    }

    func cancel(attemptID: String, claimSecret: String) async throws {
        _ = try await perform(
            .cancel(attemptID: attemptID, claimSecret: claimSecret),
            success: 204
        )
    }

    private func perform(_ action: TickTickBackendAction, success: Int) async throws -> Data {
        let token: String
        do {
            token = try await userAccessToken()
        } catch {
            throw TickTickAuthError.kiroleSignInRequired
        }
        let request = try TickTickBackendRequestBuilder.request(
            configuration: configuration,
            action: action,
            userAccessToken: token
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TickTickAuthError.invalidResponse }
        guard http.statusCode == success else {
            let code = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error) ?? "request_failed"
            switch http.statusCode {
            case 401: throw TickTickAuthError.kiroleSignInRequired
            case 409: throw TickTickAuthError.authorizationConflict
            case 410: throw TickTickAuthError.authorizationExpired
            case 429: throw TickTickAuthError.rateLimited
            default: throw TickTickAuthError.backendRejected(status: http.statusCode, code: code)
            }
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TickTickAuthError.invalidResponse
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

actor TickTickCredentialManager {
    private let region: TickTickRegion
    private let ownerUserID: String
    private let backend: any TickTickOAuthBackendServing
    private let tokenStore: any TickTickTokenStoring
    private let pendingStore: any TickTickPendingAuthorizationStoring
    private let operationGate: OAuthCredentialOperationGate

    init(
        region: TickTickRegion,
        ownerUserID: String,
        backend: any TickTickOAuthBackendServing,
        tokenStore: any TickTickTokenStoring,
        pendingStore: any TickTickPendingAuthorizationStoring,
        operationGate: OAuthCredentialOperationGate
    ) {
        self.region = region
        self.ownerUserID = ownerUserID
        self.backend = backend
        self.tokenStore = tokenStore
        self.pendingStore = pendingStore
        self.operationGate = operationGate
    }

    init(
        configuration: TickTickOAuthConfiguration,
        ownerUserID: String,
        session: URLSession = TickTickOAuthTransport.session,
        operationGate: OAuthCredentialOperationGate,
        userAccessToken: @escaping @Sendable () async throws -> String
    ) {
        region = configuration.region
        self.ownerUserID = ownerUserID
        backend = TickTickOAuthBackend(
            configuration: configuration,
            session: session,
            userAccessToken: userAccessToken
        )
        tokenStore = TickTickKeychainTokenStore(region: configuration.region)
        pendingStore = TickTickPendingAuthorizationStore(region: configuration.region)
        self.operationGate = operationGate
    }

    func startAuthorization(
        operation: OAuthCredentialOperationTicket
    ) async throws -> TickTickAuthorizationStart {
        try validate(operation)
        let start = try await backend.start(region: region)
        try validate(operation)
        guard start.pending.region == region else { throw TickTickAuthError.regionMismatch }
        let ownedPending = TickTickPendingAuthorization(
            attemptID: start.pending.attemptID,
            claimSecret: start.pending.claimSecret,
            region: start.pending.region,
            ownerUserID: ownerUserID,
            expiresAt: start.pending.expiresAt,
            delivery: nil
        )
        try validate(operation)
        try await pendingStore.save(ownedPending)
        try validate(operation)
        return TickTickAuthorizationStart(
            authorizationURL: start.authorizationURL,
            pending: ownedPending
        )
    }

    func claimAndAcknowledge(
        attemptID: String,
        operation: OAuthCredentialOperationTicket
    ) async throws -> TickTickTokenSet {
        try validate(operation)
        let storedPending = try await pendingStore.load()
        try validate(operation)
        guard var pending = storedPending,
              pending.attemptID == attemptID,
              pending.region == region,
              pending.ownerUserID == ownerUserID else {
            throw TickTickAuthError.invalidCallback
        }
        let delivery: TickTickTokenDelivery
        if let persistedDelivery = pending.delivery {
            delivery = persistedDelivery
        } else {
            try validate(operation)
            let remoteDelivery = try await backend.claim(
                attemptID: pending.attemptID,
                claimSecret: pending.claimSecret
            )
            try validate(operation)
            guard remoteDelivery.tokens.region == region else { throw TickTickAuthError.regionMismatch }
            delivery = TickTickTokenDelivery(
                deliveryID: remoteDelivery.deliveryID,
                tokens: TickTickTokenSet(
                    accessToken: remoteDelivery.tokens.accessToken,
                    expiresAt: remoteDelivery.tokens.expiresAt,
                    scope: remoteDelivery.tokens.scope,
                    accountID: remoteDelivery.tokens.accountID,
                    region: remoteDelivery.tokens.region,
                    ownerUserID: ownerUserID
                )
            )
            pending.delivery = delivery
            // Persist the delivered token before ACK. If the ACK response or process is lost,
            // the App can finish the same delivery without asking the provider to authorize again.
            try validate(operation)
            try await pendingStore.save(pending)
            try validate(operation)
        }

        try validate(operation)
        do {
            try await backend.acknowledge(
                attemptID: pending.attemptID,
                claimSecret: pending.claimSecret,
                deliveryID: delivery.deliveryID
            )
        } catch {
            try validate(operation)
            throw TickTickAuthError.deliveryAcknowledgementFailed
        }
        try validate(operation)

        try await tokenStore.save(delivery.tokens)
        try validate(operation)
        try await pendingStore.clear()
        try validate(operation)
        return delivery.tokens
    }

    func recoverPendingDelivery(
        operation: OAuthCredentialOperationTicket
    ) async throws -> TickTickTokenSet? {
        try validate(operation)
        let storedPending = try await pendingStore.load()
        try validate(operation)
        guard let pending = storedPending else { return nil }
        guard pending.ownerUserID == ownerUserID else {
            try validate(operation)
            do {
                try await pendingStore.clear()
                guard try await pendingStore.load() == nil else {
                    throw TickTickAuthError.credentialDeletionFailed
                }
            } catch {
                throw TickTickAuthError.credentialDeletionFailed
            }
            try validate(operation)
            return nil
        }
        return try await claimAndAcknowledge(attemptID: pending.attemptID, operation: operation)
    }

    func cancelPendingAuthorization(operation: OAuthCredentialOperationTicket) async throws {
        try validate(operation)
        let storedPending = try await pendingStore.load()
        try validate(operation)
        guard let pending = storedPending else { return }
        try await backend.cancel(attemptID: pending.attemptID, claimSecret: pending.claimSecret)
        try validate(operation)
        try await pendingStore.clear()
        try validate(operation)
    }

    func credentials(
        now: Date = Date(),
        operation: OAuthCredentialOperationTicket
    ) async throws -> TickTickTokenSet {
        if let recovered = try await recoverPendingDelivery(operation: operation) { return recovered }
        try validate(operation)
        let storedTokens = try await tokenStore.load()
        try validate(operation)
        guard let tokens = storedTokens else { throw TickTickAuthError.notAuthenticated }
        guard tokens.ownerUserID == ownerUserID else {
            try validate(operation)
            do {
                try await tokenStore.clear()
                guard try await tokenStore.load() == nil else {
                    throw TickTickAuthError.credentialDeletionFailed
                }
            } catch {
                throw TickTickAuthError.credentialDeletionFailed
            }
            try validate(operation)
            throw TickTickAuthError.accountMismatch
        }
        if let expiresAt = tokens.expiresAt, now >= expiresAt {
            // The official contract does not define refresh tokens. A 401 or documented expiry
            // therefore requires a new authorization instead of an invented refresh flow.
            throw TickTickAuthError.reauthorizationRequired
        }
        return tokens
    }

    func isConnected(operation: OAuthCredentialOperationTicket) async throws -> Bool {
        do {
            if try await recoverPendingDelivery(operation: operation) != nil { return true }
        } catch TickTickAuthError.credentialDeletionFailed {
            throw TickTickAuthError.credentialDeletionFailed
        } catch {
            try validate(operation)
        }
        try validate(operation)
        let tokens = try await tokenStore.load()
        try validate(operation)
        guard let tokens else { return false }
        guard tokens.ownerUserID == ownerUserID else {
            try validate(operation)
            do {
                try await tokenStore.clear()
                guard try await tokenStore.load() == nil else {
                    throw TickTickAuthError.credentialDeletionFailed
                }
            } catch {
                throw TickTickAuthError.credentialDeletionFailed
            }
            try validate(operation)
            return false
        }
        return true
    }

    private func validate(_ operation: OAuthCredentialOperationTicket) throws {
        if Task.isCancelled { throw CancellationError() }
        guard operationGate.accepts(operation) else {
            throw TickTickAuthError.credentialOperationInvalidated
        }
    }

    func disconnect() async throws {
        var remoteCleanupFailed = false
        var localError: Error?
        if let pending = try await pendingStore.load() {
            do {
                try await backend.cancel(
                    attemptID: pending.attemptID,
                    claimSecret: pending.claimSecret
                )
            } catch {
                // ACK may have reached the server just before the App stopped. In that case the
                // attempt can no longer be cancelled, but its connection metadata can be.
                if let delivery = pending.delivery {
                    do {
                        try await backend.disconnect(connectionID: delivery.tokens.accountID)
                    } catch {
                        remoteCleanupFailed = true
                    }
                } else {
                    remoteCleanupFailed = true
                }
            }
        }
        if let tokens = try await tokenStore.load() {
            do {
                try await backend.disconnect(connectionID: tokens.accountID)
            } catch {
                remoteCleanupFailed = true
            }
        }
        do {
            try await tokenStore.clear()
            guard try await tokenStore.load() == nil else {
                throw TickTickAuthError.credentialDeletionFailed
            }
        } catch {
            localError = error
        }
        do {
            try await pendingStore.clear()
            guard try await pendingStore.load() == nil else {
                throw TickTickAuthError.credentialDeletionFailed
            }
        } catch {
            localError = localError ?? error
        }
        if let localError { throw localError }
        if remoteCleanupFailed { throw TickTickAuthError.serverCleanupPending }
    }
}

@MainActor
final class TickTickAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let configuration: TickTickOAuthConfiguration
    private let credentialManager: TickTickCredentialManager
    private let operationGate: OAuthCredentialOperationGate
    private let authorizationCancellation: @MainActor () -> Void
    private var currentSession: ASWebAuthenticationSession?

    init(
        configuration: TickTickOAuthConfiguration,
        credentialManager: TickTickCredentialManager,
        operationGate: OAuthCredentialOperationGate,
        authorizationCancellation: @escaping @MainActor () -> Void = {}
    ) {
        self.configuration = configuration
        self.credentialManager = credentialManager
        self.operationGate = operationGate
        self.authorizationCancellation = authorizationCancellation
        super.init()
    }

    func authorize(operation: OAuthCredentialOperationTicket) async throws -> TickTickTokenSet {
        try validate(operation)
        let start = try await credentialManager.startAuthorization(operation: operation)
        try validate(operation)
        let callback: URL
        do {
            callback = try await performWebAuth(url: start.authorizationURL)
            try validate(operation)
            guard OAuthCallbackValidator.matches(callback, registeredRedirectURI: configuration.returnURI) else {
                throw TickTickAuthError.invalidCallback
            }
            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            guard components?.queryItems?.filter({ $0.name == "attempt_id" }).count == 1,
                  components?.queryItems?.filter({ $0.name == "status" }).count == 1,
                  let attemptID = components?.queryItems?.first(where: { $0.name == "attempt_id" })?.value,
                  attemptID == start.pending.attemptID,
                  let status = components?.queryItems?.first(where: { $0.name == "status" })?.value else {
                throw TickTickAuthError.invalidCallback
            }
            guard status == "ready" else {
                throw TickTickAuthError.providerRejected
            }
        } catch {
            // Do not leave an encrypted delivery waiting for TTL when the user cancels or the
            // browser handoff fails. If cancellation itself is offline, the server TTL remains
            // the final cleanup boundary and the local pending item is retained for retry.
            if operationGate.accepts(operation) {
                try? await credentialManager.cancelPendingAuthorization(operation: operation)
            }
            try validate(operation)
            throw error
        }
        // Once the server reports ready, do not cancel on a lost claim response. The pending
        // transaction remains in ThisDeviceOnly Keychain and can re-claim the same delivery.
        let attemptID = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "attempt_id" })?.value
        guard let attemptID else { throw TickTickAuthError.invalidCallback }
        return try await credentialManager.claimAndAcknowledge(
            attemptID: attemptID,
            operation: operation
        )
    }
    func cancelCurrentAuthorization() {
        authorizationCancellation()
        currentSession?.cancel()
        currentSession = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
        #elseif canImport(AppKit)
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        ASPresentationAnchor()
        #endif
    }

    private func performWebAuth(url: URL) async throws -> URL {
        guard #available(iOS 17.4, macOS 14.4, *),
              let callback = configuration.callbackHostAndPath else {
            throw TickTickAuthError.unsupportedSystemVersion
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: callback.host, path: callback.path)
            ) { callbackURL, error in
                Task { @MainActor in
                    self.currentSession = nil
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: TickTickAuthError.missingCallback)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            guard session.start() else {
                currentSession = nil
                continuation.resume(throwing: TickTickAuthError.invalidURL)
                return
            }
        }
    }

    private func validate(_ operation: OAuthCredentialOperationTicket) throws {
        if Task.isCancelled { throw CancellationError() }
        guard operationGate.accepts(operation) else {
            throw TickTickAuthError.credentialOperationInvalidated
        }
    }
}

import AuthenticationServices
import Foundation

// MARK: - Apple Sign In Service

/// 处理 Apple Sign In 认证流程
public final class AppleSignInService: NSObject, Sendable {
    public static let shared = AppleSignInService()

    private let keychainService = KeychainService.shared

    private override init() {
        super.init()
    }

    // MARK: - Sign In

    /// 执行 Apple Sign In
    /// - Returns: 认证结果，包含用户信息
    @MainActor
    public func signIn() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleSignInDelegate(continuation: continuation)

            // 保持 delegate 引用
            objc_setAssociatedObject(
                controller,
                "delegate",
                delegate,
                .OBJC_ASSOCIATION_RETAIN
            )

            controller.delegate = delegate
            controller.performRequests()
        }
    }

    // MARK: - Check Credential State

    /// 检查已保存的 Apple ID 凭证状态
    public func checkCredentialState() async -> ASAuthorizationAppleIDProvider.CredentialState {
        guard let userIdentifier = keychainService.getAppleUserIdentifier() else {
            return .notFound
        }

        return await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    /// 保存用户标识符
    public func saveUserIdentifier(_ identifier: String) throws {
        try keychainService.saveAppleUserIdentifier(identifier)
    }

    /// 清除保存的凭证
    public func clearCredentials() {
        keychainService.clearAppleUserIdentifier()
    }
}

// MARK: - Apple Sign In Result

public struct AppleSignInResult: Sendable {
    public let userIdentifier: String
    public let email: String?
    public let fullName: PersonNameComponents?
    public let identityToken: Data?
    public let authorizationCode: Data?

    public var displayName: String? {
        guard let fullName = fullName else { return nil }
        var components: [String] = []
        if let givenName = fullName.givenName {
            components.append(givenName)
        }
        if let familyName = fullName.familyName {
            components.append(familyName)
        }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    public var identityTokenString: String? {
        guard let token = identityToken else { return nil }
        return String(data: token, encoding: .utf8)
    }
}

// MARK: - Apple Sign In Delegate

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<AppleSignInResult, Error>

    init(continuation: CheckedContinuation<AppleSignInResult, Error>) {
        self.continuation = continuation
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation.resume(throwing: AppleSignInError.invalidCredential)
            return
        }

        let result = AppleSignInResult(
            userIdentifier: credential.user,
            email: credential.email,
            fullName: credential.fullName,
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode
        )

        continuation.resume(returning: result)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                continuation.resume(throwing: AppleSignInError.canceled)
            case .failed:
                continuation.resume(throwing: AppleSignInError.failed(authError.localizedDescription))
            case .invalidResponse:
                continuation.resume(throwing: AppleSignInError.invalidResponse)
            case .notHandled:
                continuation.resume(throwing: AppleSignInError.notHandled)
            case .unknown:
                continuation.resume(throwing: AppleSignInError.unknown)
            case .notInteractive:
                continuation.resume(throwing: AppleSignInError.notInteractive)
            case .matchedExcludedCredential:
                continuation.resume(throwing: AppleSignInError.matchedExcludedCredential)
            @unknown default:
                continuation.resume(throwing: AppleSignInError.unknown)
            }
        } else {
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - Apple Sign In Error

public enum AppleSignInError: LocalizedError, Sendable {
    case canceled
    case failed(String)
    case invalidResponse
    case invalidCredential
    case notHandled
    case unknown
    case notInteractive
    case matchedExcludedCredential

    public var errorDescription: String? {
        switch self {
        case .canceled:
            return "Sign in was canceled"
        case .failed(let message):
            return "Sign in failed: \(message)"
        case .invalidResponse:
            return "Invalid response from Apple"
        case .invalidCredential:
            return "Invalid credential received"
        case .notHandled:
            return "Authorization request not handled"
        case .unknown:
            return "An unknown error occurred"
        case .notInteractive:
            return "Authorization requires user interaction"
        case .matchedExcludedCredential:
            return "Credential matched an excluded credential"
        }
    }
}

import Foundation
import Supabase

enum AccountDeletionRemotePolicy {
    /// Local wipe is allowed only when the cloud account is already gone.
    /// Client-local failures (`notConfigured`, `noSession`) and expired/invalid
    /// credentials fail closed so a still-living account is not abandoned.
    static func canFinishLocallyAfterRemoteError(_ error: Error) -> Bool {
        if error is SupabaseError {
            return false
        }
        return isDeletedCloudSession(error)
    }

    static func isDeletedCloudStatus(_ statusCode: Int) -> Bool {
        statusCode == 401
    }

    /// True after a delete RPC against a live session comes back as "user already gone".
    static func isDeletedCloudSession(_ error: Error) -> Bool {
        if let auth = error as? AuthError {
            return isDeletedCloudAuthError(auth)
        }
        if let http = error as? HTTPError {
            return isDeletedCloudStatus(http.response.statusCode)
        }
        if let postgrest = error as? PostgrestError {
            return isDeletedCloudPostgrest(postgrest)
        }
        return false
    }

    /// Test seam: supabase-swift's 401 after `auth.users` is already gone.
    static func httpError(statusCode: Int) -> Error {
        HTTPError(
            data: Data(),
            response: HTTPURLResponse(
                url: URL(string: "https://outku3.zeabur.app/rest/v1/rpc/delete_own_account")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    static func authAPIError(code: String, statusCode: Int) -> Error {
        AuthError.api(
            message: code,
            errorCode: ErrorCode(code),
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(
                url: URL(string: "https://outku3.zeabur.app/auth/v1/user")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    static func jwtVerificationFailedError() -> Error {
        AuthError.jwtVerificationFailed(message: "invalid jwt")
    }

    static func sessionMissingError() -> Error {
        AuthError.sessionMissing
    }

    static func postgrestError(code: String?, message: String) -> Error {
        PostgrestError(code: code, message: message)
    }

    private static func isDeletedCloudAuthError(_ error: AuthError) -> Bool {
        switch error {
        case .sessionMissing:
            return true
        case let .api(_, errorCode, _, response):
            if isDeletedCloudStatus(response.statusCode) {
                return true
            }
            return deletedAccountAuthCodes.contains(errorCode)
        default:
            return false
        }
    }

    private static func isDeletedCloudPostgrest(_ error: PostgrestError) -> Bool {
        if let code = error.code?.lowercased(), code == "user_not_found" {
            return true
        }
        return error.message.lowercased().contains("user not found")
    }

    private static let deletedAccountAuthCodes: Set<ErrorCode> = [
        .userNotFound,
        .sessionNotFound
    ]
}

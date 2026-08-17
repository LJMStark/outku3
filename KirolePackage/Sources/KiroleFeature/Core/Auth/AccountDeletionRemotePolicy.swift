import Foundation
import Supabase

enum AccountDeletionRemotePolicy {
    static func canFinishLocallyAfterRemoteError(_ error: Error) -> Bool {
        if let supabase = error as? SupabaseError {
            switch supabase {
            case .notConfigured, .noSession:
                return true
            case .sessionUserMismatch:
                return false
            }
        }
        return isDeletedCloudSession(error)
    }

    static func isDeletedCloudStatus(_ statusCode: Int) -> Bool {
        statusCode == 401
    }

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

    private static func isDeletedCloudAuthError(_ error: AuthError) -> Bool {
        switch error {
        case .sessionMissing, .jwtVerificationFailed:
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
        if let code = error.code?.lowercased(),
           code == "pgrst301" || code.contains("jwt") {
            return true
        }
        let message = error.message.lowercased()
        return message.contains("jwt")
            || message.contains("not authenticated")
            || message.contains("user not found")
    }

    private static let deletedAccountAuthCodes: Set<ErrorCode> = [
        .badJWT,
        .invalidJWT,
        .noAuthorization,
        .userNotFound,
        .sessionNotFound,
        .sessionExpired,
        .invalidCredentials
    ]
}

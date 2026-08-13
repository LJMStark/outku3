import Foundation

enum OAuthCallbackValidator {
    /// OAuth callbacks may add query parameters, but their registered redirect origin and path
    /// must match exactly. This prevents another callback route sharing the app's URL scheme from
    /// being accepted by the wrong provider flow.
    static func matches(_ callbackURL: URL, registeredRedirectURI: URL) -> Bool {
        guard let callback = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        ), let registered = URLComponents(
            url: registeredRedirectURI,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }

        return callback.scheme?.caseInsensitiveCompare(registered.scheme ?? "") == .orderedSame
            && callback.host?.caseInsensitiveCompare(registered.host ?? "") == .orderedSame
            && callback.port == registered.port
            && callback.percentEncodedPath == registered.percentEncodedPath
            && callback.user == registered.user
            && callback.password == registered.password
    }
}

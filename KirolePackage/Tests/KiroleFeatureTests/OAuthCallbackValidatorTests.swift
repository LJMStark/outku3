import Foundation
import Testing
@testable import KiroleFeature

@Suite("Provider OAuth callback validation")
struct OAuthCallbackValidatorTests {
    @Test("Accepts provider query parameters only on the registered callback route")
    func acceptsRegisteredRoute() throws {
        let registered = try #require(URL(string: "kirole://todoist-callback"))
        let callback = try #require(URL(
            string: "kirole://todoist-callback?code=authorization-code&state=random-state"
        ))

        #expect(OAuthCallbackValidator.matches(
            callback,
            registeredRedirectURI: registered
        ))
    }

    @Test("Rejects another provider route that shares the same custom URL scheme")
    func rejectsSharedSchemeRoute() throws {
        let registered = try #require(URL(string: "kirole://todoist-callback"))
        let wrongHost = try #require(URL(
            string: "kirole://ticktick-callback?code=authorization-code&state=random-state"
        ))

        #expect(!OAuthCallbackValidator.matches(
            wrongHost,
            registeredRedirectURI: registered
        ))
    }
}

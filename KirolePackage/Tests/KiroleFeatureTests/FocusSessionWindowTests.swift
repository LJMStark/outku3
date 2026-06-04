import Testing
import Foundation
@testable import KiroleFeature

// Guards the `count > 0` short-circuit in LocalStorage.loadFocusSessionsForPastDays.
// `1...count` is a closed range that traps (uncatchable precondition failure) when
// count < 1, so a non-positive window must return [] before the range is formed.
// count <= 0 short-circuits before any disk access, so these are deterministic and
// need no fixtures or cleanup.
@Suite("Focus Session Window Bounds")
struct FocusSessionWindowTests {

    @Test("Non-positive day window returns [] without trapping", arguments: [0, -1, -7])
    func nonPositiveWindowReturnsEmpty(count: Int) async throws {
        let sessions = try await LocalStorage.shared.loadFocusSessionsForPastDays(count)
        #expect(sessions.isEmpty)
    }
}

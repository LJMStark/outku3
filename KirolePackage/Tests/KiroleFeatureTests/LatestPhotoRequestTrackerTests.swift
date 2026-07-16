import Testing
@testable import KiroleFeature

@Suite("Latest Photo Request Tracker Tests")
struct LatestPhotoRequestTrackerTests {
    @Test("A slower request cannot replace a newer request")
    func newerRequestSupersedesOlderRequest() {
        var tracker = LatestPhotoRequestTracker()

        let requestA = tracker.begin()
        let requestB = tracker.begin()

        #expect(!tracker.isCurrent(requestA))
        #expect(tracker.isCurrent(requestB))
    }

    @Test("Invalidating rejects the in-flight request")
    func invalidateRejectsCurrentRequest() {
        var tracker = LatestPhotoRequestTracker()

        let request = tracker.begin()
        tracker.invalidate()

        #expect(!tracker.isCurrent(request))
    }
}

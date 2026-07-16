struct LatestPhotoRequestTracker: Sendable {
    private var generation: UInt64 = 0

    mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ requestID: UInt64) -> Bool {
        requestID == generation
    }
}

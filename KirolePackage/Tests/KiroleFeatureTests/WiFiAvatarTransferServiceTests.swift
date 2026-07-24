import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("WiFi Avatar Transfer Service", .serialized)
struct WiFiAvatarTransferServiceTests {

    // MARK: - Mocks

    final class MockSession: WiFiAvatarSessionHandshaking, @unchecked Sendable {
        let openResult: Result<WiFiAvatarSessionCredentials, any Error>
        private(set) var openCount = 0
        private(set) var closeCount = 0
        private(set) var closeWasCancelled = false
        init(_ openResult: Result<WiFiAvatarSessionCredentials, any Error>) { self.openResult = openResult }
        func openSession(operationID: UInt32) async throws -> WiFiAvatarSessionCredentials {
            openCount += 1
            return try openResult.get()
        }
        func closeSession(operationID: UInt32) async {
            closeCount += 1
            closeWasCancelled = Task.isCancelled
        }
    }

    final class MockHotspot: HotspotJoining, @unchecked Sendable {
        let joinError: (any Error)?
        private(set) var joinCount = 0
        private(set) var leaveCount = 0
        init(joinError: (any Error)? = nil) { self.joinError = joinError }
        func join(ssid: String, passphrase: String) async throws {
            joinCount += 1
            if let joinError { throw joinError }
        }
        func leave(ssid: String) async { leaveCount += 1 }
    }

    final class MockReachability: WiFiReachability, @unchecked Sendable {
        let associationSatisfied: Bool
        private(set) var expectedSSIDs: [String] = []
        init(associationSatisfied: Bool = true) {
            self.associationSatisfied = associationSatisfied
        }
        func waitUntilAssociated(to ssid: String, timeout: Duration) async -> Bool {
            expectedSSIDs.append(ssid)
            return associationSatisfied
        }
    }

    final class CancellationAwareReachability: WiFiReachability, @unchecked Sendable {
        private(set) var didStart = false

        func waitUntilAssociated(to ssid: String, timeout: Duration) async -> Bool {
            didStart = true
            while !Task.isCancelled { await Task.yield() }
            return false
        }
    }

    final class MockUploader: AvatarHTTPUploading, @unchecked Sendable {
        let uploadError: (any Error)?
        let progressToEmit: [(Int, Int)]
        private(set) var uploadCount = 0
        private(set) var lastHeaders: [String: String] = [:]
        private(set) var lastEndpoint: URL?
        init(uploadError: (any Error)? = nil, progressToEmit: [(Int, Int)] = []) {
            self.uploadError = uploadError
            self.progressToEmit = progressToEmit
        }
        func upload(
            kriData: Data,
            to endpoint: URL,
            headers: [String: String],
            onProgress: @escaping @Sendable (Int, Int) -> Void
        ) async throws {
            uploadCount += 1
            lastHeaders = headers
            lastEndpoint = endpoint
            for (sent, total) in progressToEmit { onProgress(sent, total) }
            if let uploadError { throw uploadError }
        }
    }

    @MainActor final class ProgressCollector {
        var values: [[Int]] = []
        func record(_ sent: Int, _ total: Int) { values.append([sent, total]) }
    }

    // MARK: - Helpers

    private static func credentials() -> WiFiAvatarSessionCredentials {
        WiFiAvatarSessionCredentials(
            ssid: "Kirole-TEST",
            passphrase: "pw",
            gateway: IPv4Address(192, 168, 4, 1),
            port: 8080,
            path: "/avatar",
            token: "tok",
            ttlSeconds: 120
        )
    }

    private func makeService(
        session: MockSession,
        hotspot: MockHotspot = MockHotspot(),
        reachability: any WiFiReachability = MockReachability(),
        uploader: MockUploader = MockUploader()
    ) -> WiFiAvatarTransferService {
        WiFiAvatarTransferService(
            session: session,
            hotspot: hotspot,
            reachability: reachability,
            uploader: uploader,
            pathTimeout: .milliseconds(50)
        )
    }

    // MARK: - Tests

    @Test("Successful transfer joins, uploads, and cleans up")
    func successfulTransfer() async throws {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot()
        let uploader = MockUploader()
        let service = makeService(session: session, hotspot: hotspot, uploader: uploader)

        var phases: [WiFiTransferPhase] = []
        try await service.send(
            operationID: 0x1234,
            avatarID: UUID(),
            kriData: Data([1, 2, 3, 4]),
            onPhase: { phases.append($0) },
            onProgress: { _, _ in }
        )

        #expect(phases == [.joiningHotspot, .uploading])
        #expect(session.openCount == 1)
        #expect(hotspot.joinCount == 1)
        #expect(uploader.uploadCount == 1)
        // cleanup always runs
        #expect(hotspot.leaveCount == 1)
        #expect(session.closeCount == 1)
        #expect(!session.closeWasCancelled)
        #expect(uploader.lastEndpoint?.absoluteString == "http://192.168.4.1:8080/avatar")
    }

    @Test("No current WiFi path does not block opening the device hotspot")
    func noCurrentWiFiPathDoesNotBlockSession() async throws {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot()
        let service = makeService(
            session: session,
            hotspot: hotspot,
            reachability: MockReachability(associationSatisfied: true)
        )

        try await service.send(
            operationID: 1,
            avatarID: UUID(),
            kriData: Data(),
            onPhase: { _ in },
            onProgress: { _, _ in }
        )

        #expect(session.openCount == 1)
        #expect(hotspot.joinCount == 1)
        #expect(hotspot.leaveCount == 1)
        #expect(session.closeCount == 1)
        #expect(!session.closeWasCancelled)
    }

    @Test("Session handshake failure closes the operation and skips the transfer")
    func sessionHandshakeFailsAndCloses() async {
        let session = MockSession(.failure(WiFiAvatarSessionError.timedOut))
        let hotspot = MockHotspot()
        let uploader = MockUploader()
        let service = makeService(session: session, hotspot: hotspot, uploader: uploader)

        await #expect(throws: WiFiTransferError.self) {
            try await service.send(operationID: 1, avatarID: UUID(), kriData: Data(), onPhase: { _ in }, onProgress: { _, _ in })
        }
        #expect(hotspot.joinCount == 0)
        #expect(uploader.uploadCount == 0)
        #expect(hotspot.leaveCount == 0)
        #expect(session.closeCount == 1)
    }

    @Test("Hotspot join failure cleans up the opened session")
    func hotspotJoinFails() async {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot(joinError: HotspotJoinError.userDenied)
        let uploader = MockUploader()
        let service = makeService(session: session, hotspot: hotspot, uploader: uploader)

        await #expect(throws: WiFiTransferError.self) {
            try await service.send(operationID: 1, avatarID: UUID(), kriData: Data(), onPhase: { _ in }, onProgress: { _, _ in })
        }
        #expect(uploader.uploadCount == 0)
        #expect(hotspot.leaveCount == 1) // cleanup ran
        #expect(session.closeCount == 1)
    }

    @Test("Unreachable WiFi path cleans up without uploading")
    func unreachablePath() async {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot()
        let uploader = MockUploader()
        let service = makeService(
            session: session,
            hotspot: hotspot,
            reachability: MockReachability(associationSatisfied: false),
            uploader: uploader
        )

        await #expect(throws: WiFiTransferError.unreachable) {
            try await service.send(operationID: 1, avatarID: UUID(), kriData: Data(), onPhase: { _ in }, onProgress: { _, _ in })
        }
        #expect(uploader.uploadCount == 0)
        #expect(hotspot.leaveCount == 1)
        #expect(session.closeCount == 1)
        #expect(!session.closeWasCancelled)
    }

    @Test("A WiFi path on another SSID never uploads the avatar")
    func differentSSIDDoesNotUpload() async {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot()
        let reachability = MockReachability(associationSatisfied: false)
        let uploader = MockUploader()
        let service = makeService(
            session: session,
            hotspot: hotspot,
            reachability: reachability,
            uploader: uploader
        )

        await #expect(throws: WiFiTransferError.unreachable) {
            try await service.send(
                operationID: 1,
                avatarID: UUID(),
                kriData: Data([1]),
                onPhase: { _ in },
                onProgress: { _, _ in }
            )
        }

        #expect(reachability.expectedSSIDs == ["Kirole-TEST"])
        #expect(uploader.uploadCount == 0)
        #expect(hotspot.leaveCount == 1)
        #expect(session.closeCount == 1)
        #expect(!session.closeWasCancelled)
    }

    @Test("Cancellation while waiting for the target SSID does not fall back as unreachable")
    func associationCancellationRemainsCancellation() async {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot()
        let reachability = CancellationAwareReachability()
        let uploader = MockUploader()
        let service = makeService(
            session: session,
            hotspot: hotspot,
            reachability: reachability,
            uploader: uploader
        )

        let task = Task {
            try await service.send(
                operationID: 1,
                avatarID: UUID(),
                kriData: Data([1]),
                onPhase: { _ in },
                onProgress: { _, _ in }
            )
        }
        while !reachability.didStart { await Task.yield() }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(uploader.uploadCount == 0)
        #expect(hotspot.leaveCount == 1)
        #expect(session.closeCount == 1)
        #expect(!session.closeWasCancelled)
    }

    @Test("HTTP upload failure cleans up")
    func httpUploadFails() async {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot()
        let uploader = MockUploader(uploadError: AvatarHTTPUploadError.httpStatus(409))
        let service = makeService(session: session, hotspot: hotspot, uploader: uploader)

        await #expect(throws: WiFiTransferError.self) {
            try await service.send(operationID: 1, avatarID: UUID(), kriData: Data([9]), onPhase: { _ in }, onProgress: { _, _ in })
        }
        #expect(hotspot.leaveCount == 1)
        #expect(session.closeCount == 1)
    }

    @Test("Cancellation during upload cleans up and remains cancellation")
    func uploadCancellationCleansUp() async {
        let session = MockSession(.success(Self.credentials()))
        let hotspot = MockHotspot()
        let uploader = MockUploader(uploadError: CancellationError())
        let service = makeService(session: session, hotspot: hotspot, uploader: uploader)

        await #expect(throws: CancellationError.self) {
            try await service.send(
                operationID: 1,
                avatarID: UUID(),
                kriData: Data([9]),
                onPhase: { _ in },
                onProgress: { _, _ in }
            )
        }
        #expect(hotspot.leaveCount == 1)
        #expect(session.closeCount == 1)
        #expect(!session.closeWasCancelled)
    }

    @Test("Upload progress is forwarded to the caller")
    func progressForwarded() async throws {
        let session = MockSession(.success(Self.credentials()))
        let uploader = MockUploader(progressToEmit: [(500, 1000), (1000, 1000)])
        let service = makeService(session: session, uploader: uploader)
        let collector = ProgressCollector()

        try await service.send(
            operationID: 1,
            avatarID: UUID(),
            kriData: Data([1]),
            onPhase: { _ in },
            onProgress: { sent, total in collector.record(sent, total) }
        )

        // onProgress hops to the main actor via Task; spin until both land.
        var spins = 0
        while collector.values.count < 2, spins < 1000 {
            await Task.yield()
            spins += 1
        }
        #expect(collector.values == [[500, 1000], [1000, 1000]])
    }

    @Test("Upload headers carry operation, avatar, length, CRC and bearer token")
    func headersAreWellFormed() throws {
        let avatarID = UUID()
        let headers = WiFiAvatarTransferService.uploadHeaders(
            operationID: 0x0000_ABCD,
            avatarID: avatarID,
            byteLength: 2_240_012,
            crc32: 0x1234_5678,
            token: "sekret"
        )
        #expect(headers[WiFiAvatarHTTPContract.authorizationHeader] == "Bearer sekret")
        #expect(headers[WiFiAvatarHTTPContract.operationIDHeader] == "0000abcd")
        #expect(headers[WiFiAvatarHTTPContract.avatarIDHeader] == avatarID.uuidString)
        #expect(headers[WiFiAvatarHTTPContract.fileLengthHeader] == "2240012")
        #expect(headers[WiFiAvatarHTTPContract.fileCRC32Header] == "12345678")
    }

    @Test("SSID association requires identical UTF-8 bytes")
    func ssidAssociationUsesExactBytes() {
        let composed = "Caf\u{00E9}-AP"
        let decomposed = "Cafe\u{0301}-AP"

        #expect(composed == decomposed) // Swift String equality is normalization-aware.
        #expect(WiFiSSIDMatcher.matches(composed, expected: composed))
        #expect(!WiFiSSIDMatcher.matches(decomposed, expected: composed))
        #expect(!WiFiSSIDMatcher.matches(nil, expected: composed))
    }

}

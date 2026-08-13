import Foundation
import os
import Testing
@testable import KiroleFeature

@Suite("TickTick API rate limiting", .serialized)
struct TickTickAPIRetryTests {
    @Test("A 429 response honors Retry-After before retrying once")
    func retryAfterRateLimit() async throws {
        TickTickRateLimitURLProtocol.reset(retryAfter: "12")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TickTickRateLimitURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delays = TickTickRetryDelayRecorder()
        let api = TickTickAPI(
            region: .international,
            session: session,
            rateLimitSleep: { delay in await delays.append(delay) }
        )

        let projects = try await api.projects(accessToken: "token")

        #expect(projects.map(\.id) == ["p1"])
        #expect(TickTickRateLimitURLProtocol.requestCount == 2)
        #expect(await delays.values() == [12])
    }

    @Test("An excessive Retry-After value is capped")
    func retryAfterIsBounded() async throws {
        TickTickRateLimitURLProtocol.reset(retryAfter: "3600")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TickTickRateLimitURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delays = TickTickRetryDelayRecorder()
        let api = TickTickAPI(
            region: .international,
            session: session,
            rateLimitSleep: { delay in await delays.append(delay) }
        )

        _ = try await api.projects(accessToken: "token")

        #expect(await delays.values() == [30])
    }
}

private final class TickTickRateLimitURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State: Sendable {
        var requestCount = 0
        var retryAfter = "0"
    }

    private static let lock = OSAllocatedUnfairLock(initialState: State())

    static var requestCount: Int {
        lock.withLock(\.requestCount)
    }

    static func reset(retryAfter: String) {
        lock.withLock {
            $0 = State(requestCount: 0, retryAfter: retryAfter)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.ticktick.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let state = Self.lock.withLock { value in
            value.requestCount += 1
            return value
        }
        let statusCode = state.requestCount == 1 ? 429 : 200
        let headers = state.requestCount == 1
            ? ["Content-Type": "application/json", "Retry-After": state.retryAfter]
            : ["Content-Type": "application/json"]
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let data = state.requestCount == 1
            ? Data(#"{"error":"rate_limited"}"#.utf8)
            : Data(#"[{"id":"p1","name":"Work"}]"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor TickTickRetryDelayRecorder {
    private var delays: [TimeInterval] = []

    func append(_ delay: TimeInterval) {
        delays.append(delay)
    }

    func values() -> [TimeInterval] {
        delays
    }
}

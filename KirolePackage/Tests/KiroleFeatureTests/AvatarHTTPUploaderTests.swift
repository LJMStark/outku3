import Foundation
import Testing
@testable import KiroleFeature

@Suite("Avatar HTTP Uploader", .serialized)
struct AvatarHTTPUploaderTests {
    @Test("HTTP 200 is the only successful response")
    func http200Succeeds() async throws {
        try await makeUploader().upload(
            kriData: Data([0x01]),
            to: try #require(URL(string: "http://stub.kirole/status/200")),
            headers: [:],
            onProgress: { _, _ in }
        )
    }

    @Test("Non-200 2xx responses are rejected", arguments: [201, 204, 299])
    func non200SuccessClassIsRejected(statusCode: Int) async throws {
        let endpoint = try #require(URL(string: "http://stub.kirole/status/\(statusCode)"))

        await #expect(throws: AvatarHTTPUploadError.httpStatus(statusCode)) {
            try await makeUploader().upload(
                kriData: Data([0x01]),
                to: endpoint,
                headers: [:],
                onProgress: { _, _ in }
            )
        }
    }

    @Test("HTTP redirects are rejected instead of forwarding avatar bytes")
    func redirectIsRejected() async throws {
        final class Decision: @unchecked Sendable {
            var didComplete = false
            var request: URLRequest?
        }

        let originalURL = try #require(URL(string: "http://192.168.4.1/avatar"))
        let redirectedURL = try #require(URL(string: "http://example.com/avatar"))
        let response = try #require(HTTPURLResponse(
            url: originalURL,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectedURL.absoluteString]
        ))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: originalURL)
        let decision = Decision()
        let delegate = UploadProgressDelegate { _, _ in }

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectedURL)
        ) { request in
            decision.didComplete = true
            decision.request = request
        }

        #expect(decision.didComplete)
        #expect(decision.request == nil)
    }

    @Test("Cancelling an upload remains CancellationError")
    func cancellationIsPreserved() async throws {
        let endpoint = try #require(URL(string: "http://stub.kirole/delay"))
        let task = Task {
            try await makeUploader().upload(
                kriData: Data([0x01]),
                to: endpoint,
                headers: [:],
                onProgress: { _, _ in }
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func makeUploader() -> URLSessionAvatarUploader {
        URLSessionAvatarUploader(timeout: 1) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AvatarHTTPStatusURLProtocol.self]
            return configuration
        }
    }
}

private final class AvatarHTTPStatusURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.kirole"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if url.lastPathComponent == "delay" {
            return
        }
        guard
              let statusCode = Int(url.lastPathComponent),
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

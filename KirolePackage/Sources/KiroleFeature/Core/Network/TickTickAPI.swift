import Foundation

private final class TickTickAPINoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum TickTickAPITransport {
    static let session = URLSession(
        configuration: .ephemeral,
        delegate: TickTickAPINoRedirectDelegate(),
        delegateQueue: nil
    )
}

public protocol TickTickReadServing: Sendable {
    func projects(accessToken: String) async throws -> [TickTickProject]
    func projectData(
        projectID: String,
        accessToken: String,
        ifNoneMatch: String?
    ) async throws -> TickTickConditionalProjectData
}

public actor TickTickAPI: TickTickReadServing {
    private let region: TickTickRegion
    private let session: URLSession
    private let rateLimitSleep: @Sendable (TimeInterval) async throws -> Void

    private static let maxRateLimitRetries = 1
    private static let maximumRetryDelay: TimeInterval = 30

    public init(region: TickTickRegion) {
        self.region = region
        session = TickTickAPITransport.session
        rateLimitSleep = Self.defaultRateLimitSleep
    }

    public init(region: TickTickRegion, session: URLSession) {
        self.region = region
        self.session = session
        rateLimitSleep = Self.defaultRateLimitSleep
    }

    init(
        region: TickTickRegion,
        session: URLSession,
        rateLimitSleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.region = region
        self.session = session
        self.rateLimitSleep = rateLimitSleep
    }

    public func projects(accessToken: String) async throws -> [TickTickProject] {
        let request = authenticatedRequest(
            url: region.apiBaseURL.appendingPathComponent("project"),
            accessToken: accessToken
        )
        let (data, response) = try await data(for: request)
        try Self.validate(response, data: data, expectedHost: request.url?.host)
        return try JSONDecoder().decode([TickTickProject].self, from: data)
    }

    public func projectData(
        projectID: String,
        accessToken: String,
        ifNoneMatch: String?
    ) async throws -> TickTickConditionalProjectData {
        let dataURL = region.apiBaseURL
            .appendingPathComponent("project")
            .appendingPathComponent(projectID)
            .appendingPathComponent("data")
        var request = authenticatedRequest(
            url: dataURL,
            accessToken: accessToken
        )
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TickTickAPIError.invalidResponse }
        try Self.validateOrigin(http, expectedHost: request.url?.host)
        if http.statusCode == 304 { return .notModified }
        try Self.validate(http, data: data, expectedHost: request.url?.host)
        let payload = try JSONDecoder().decode(TickTickProjectData.self, from: data)
        return .modified(data: payload, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    private func authenticatedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return request
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        for attempt in 0...Self.maxRateLimitRetries {
            let result = try await session.data(for: request)
            guard let response = result.1 as? HTTPURLResponse else {
                throw TickTickAPIError.invalidResponse
            }
            try Self.validateOrigin(response, expectedHost: request.url?.host)
            guard response.statusCode == 429,
                  attempt < Self.maxRateLimitRetries else {
                return result
            }
            let delay = Self.retryDelay(
                retryAfter: response.value(forHTTPHeaderField: "Retry-After")
            )
            try await rateLimitSleep(delay)
        }
        throw TickTickAPIError.invalidResponse
    }

    private nonisolated static func retryDelay(retryAfter: String?) -> TimeInterval {
        if let retryAfter,
           let seconds = TimeInterval(retryAfter),
           seconds >= 0 {
            return min(seconds, maximumRetryDelay)
        }
        if let retryAfter,
           let date = retryAfterDateFormatter.date(from: retryAfter) {
            return min(max(0, date.timeIntervalSinceNow), maximumRetryDelay)
        }
        return 1
    }

    private nonisolated static var retryAfterDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }

    private nonisolated static func defaultRateLimitSleep(_ delay: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(delay))
    }

    private static func validate(
        _ response: URLResponse,
        data: Data,
        expectedHost: String?
    ) throws {
        guard let http = response as? HTTPURLResponse else { throw TickTickAPIError.invalidResponse }
        try validateOrigin(http, expectedHost: expectedHost)
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw TickTickAPIError.httpStatus(http.statusCode, detail)
        }
    }

    private static func validateOrigin(_ response: HTTPURLResponse, expectedHost: String?) throws {
        guard response.url?.scheme == "https",
              response.url?.host == expectedHost else {
            throw TickTickAPIError.invalidResponse
        }
    }
}

public enum TickTickAPIError: LocalizedError, Sendable, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "TickTick returned an invalid HTTP response"
        case .httpStatus(let status, let detail):
            "TickTick request failed (HTTP \(status))\(detail.map { ": \($0)" } ?? "")"
        }
    }
}

import Foundation

// MARK: - Transport

struct MicrosoftHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]
}

protocol MicrosoftGraphTransport: Sendable {
    func send(_ request: URLRequest) async throws -> MicrosoftHTTPResponse
}

struct URLSessionMicrosoftGraphTransport: MicrosoftGraphTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> MicrosoftHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MicrosoftGraphError.invalidResponse
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key).lowercased()] = String(describing: pair.value)
        }
        return MicrosoftHTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
    }
}

// MARK: - Delta batch

struct MicrosoftDeltaBatch<Item: Sendable>: Sendable {
    let items: [Item]
    let deltaLink: String
}

// MARK: - Client

/// Microsoft Graph v1.0 client for the global cloud.
///
/// Stored next/delta links are treated as opaque, but their host is validated before attaching a
/// bearer token. The client follows paging until Graph returns a delta link and retries bounded
/// throttling/transient failures using Retry-After when provided.
public actor MicrosoftGraphClient {
    public static let shared = MicrosoftGraphClient()

    private let transport: any MicrosoftGraphTransport
    private let accessToken: @Sendable () async throws -> String
    private let forceRefreshToken: @Sendable () async throws -> String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private static let graphHost = "graph.microsoft.com"
    private static let baseURL = "https://graph.microsoft.com/v1.0"
    private static let maxPages = 100
    private static let maxTransientRetries = 3

    private init() {
        self.transport = URLSessionMicrosoftGraphTransport()
        self.accessToken = { try await MicrosoftTokenProvider.shared.accessToken() }
        self.forceRefreshToken = { try await MicrosoftTokenProvider.shared.forceRefresh() }
    }

    init(
        transport: any MicrosoftGraphTransport,
        accessToken: @escaping @Sendable () async throws -> String,
        forceRefreshToken: @escaping @Sendable () async throws -> String
    ) {
        self.transport = transport
        self.accessToken = accessToken
        self.forceRefreshToken = forceRefreshToken
    }

    // MARK: Outlook default calendar

    func fetchDefaultCalendarDelta(
        deltaLink: String?,
        start: Date,
        end: Date,
        accessToken: String? = nil
    ) async throws -> MicrosoftDeltaBatch<MicrosoftOutlookEvent> {
        let initialURL: URL
        if let deltaLink {
            initialURL = try validatedGraphURL(deltaLink)
        } else {
            guard var components = URLComponents(string: "\(Self.baseURL)/me/calendarView/delta") else {
                throw MicrosoftGraphError.invalidURL
            }
            components.queryItems = [
                URLQueryItem(name: "startDateTime", value: Self.graphDateFormatter.string(from: start)),
                URLQueryItem(name: "endDateTime", value: Self.graphDateFormatter.string(from: end)),
            ]
            guard let url = components.url else { throw MicrosoftGraphError.invalidURL }
            initialURL = url
        }

        return try await fetchAllPages(
            initialURL: initialURL,
            additionalHeaders: [
                "Prefer": "IdType=\"ImmutableId\", outlook.timezone=\"UTC\""
            ],
            itemType: MicrosoftOutlookEvent.self,
            boundAccessToken: accessToken
        )
    }

    // MARK: Microsoft To Do

    func fetchTodoListsDelta(
        deltaLink: String?,
        accessToken: String? = nil
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoList> {
        let url = try deltaLink.map(validatedGraphURL)
            ?? requireURL("\(Self.baseURL)/me/todo/lists/delta")
        return try await fetchAllPages(
            initialURL: url,
            additionalHeaders: [:],
            itemType: MicrosoftTodoList.self,
            boundAccessToken: accessToken
        )
    }

    func fetchTodoTasksDelta(
        listID: String,
        deltaLink: String?,
        accessToken: String? = nil
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoTask> {
        let url: URL
        if let deltaLink {
            url = try validatedGraphURL(deltaLink)
        } else {
            let encodedListID = try pathComponent(listID)
            guard var components = URLComponents(
                string: "\(Self.baseURL)/me/todo/lists/\(encodedListID)/tasks/delta"
            ) else {
                throw MicrosoftGraphError.invalidURL
            }
            components.queryItems = [URLQueryItem(
                name: "$select",
                value: "id,title,status,dueDateTime,importance,lastModifiedDateTime,body"
            )]
            guard let selectedURL = components.url else {
                throw MicrosoftGraphError.invalidURL
            }
            url = selectedURL
        }
        return try await fetchAllPages(
            initialURL: url,
            additionalHeaders: ["Prefer": "outlook.timezone=\"UTC\""],
            itemType: MicrosoftTodoTask.self,
            boundAccessToken: accessToken
        )
    }

    func updateTodoTaskStatus(
        listID: String,
        taskID: String,
        status: MicrosoftTodoStatus,
        accessToken: String? = nil
    ) async throws {
        let encodedListID = try pathComponent(listID)
        let encodedTaskID = try pathComponent(taskID)
        let url = try requireURL(
            "\(Self.baseURL)/me/todo/lists/\(encodedListID)/tasks/\(encodedTaskID)"
        )
        let body = try encoder.encode(MicrosoftTodoTaskPatch(status: status.rawValue))
        _ = try await request(
            url: url,
            method: "PATCH",
            additionalHeaders: [:],
            body: body,
            boundAccessToken: accessToken
        )
    }

    // MARK: Paging

    private func fetchAllPages<Item: Decodable & Sendable>(
        initialURL: URL,
        additionalHeaders: [String: String],
        itemType: Item.Type,
        boundAccessToken: String?
    ) async throws -> MicrosoftDeltaBatch<Item> {
        var items: [Item] = []
        var nextURL: URL? = initialURL

        for _ in 0..<Self.maxPages {
            guard let pageURL = nextURL else { break }
            let data = try await request(
                url: pageURL,
                method: "GET",
                additionalHeaders: additionalHeaders,
                body: nil,
                boundAccessToken: boundAccessToken
            )
            let page = try decoder.decode(MicrosoftGraphPage<Item>.self, from: data)
            items.append(contentsOf: page.value)

            if let nextLink = page.nextLink {
                nextURL = try validatedGraphURL(nextLink)
                continue
            }
            guard let deltaLink = page.deltaLink else {
                throw MicrosoftGraphError.missingDeltaLink
            }
            _ = itemType
            return MicrosoftDeltaBatch(items: items, deltaLink: deltaLink)
        }

        throw MicrosoftGraphError.pageLimitExceeded
    }

    // MARK: Requests

    private func request(
        url: URL,
        method: String,
        additionalHeaders: [String: String],
        body: Data?,
        boundAccessToken: String?
    ) async throws -> Data {
        _ = try validatedGraphURL(url.absoluteString)
        var token: String
        if let boundAccessToken {
            token = boundAccessToken
        } else {
            token = try await accessToken()
        }
        let allowsTokenRefresh = boundAccessToken == nil
        var refreshedUnauthorizedToken = false

        for attempt in 0...Self.maxTransientRetries {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            additionalHeaders.forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.httpBody = body

            let response = try await transport.send(request)
            switch response.statusCode {
            case 200...299:
                return response.data
            case 401 where allowsTokenRefresh && !refreshedUnauthorizedToken:
                token = try await forceRefreshToken()
                refreshedUnauthorizedToken = true
                continue
            case 410:
                throw MicrosoftGraphError.deltaTokenExpired
            case 412:
                throw MicrosoftGraphError.preconditionFailed
            case 429 where attempt < Self.maxTransientRetries:
                let retryDelay = Self.retryDelay(
                    attempt: attempt,
                    retryAfter: response.headers["retry-after"]
                )
                try await Task.sleep(for: .seconds(retryDelay))
                continue
            case 500...599 where attempt < Self.maxTransientRetries:
                let retryDelay = Self.retryDelay(
                    attempt: attempt,
                    retryAfter: response.headers["retry-after"]
                )
                try await Task.sleep(for: .seconds(retryDelay))
                continue
            default:
                throw MicrosoftGraphError.httpError(
                    response.statusCode,
                    Self.errorMessage(from: response.data)
                )
            }
        }

        throw MicrosoftGraphError.retryLimitExceeded
    }

    // MARK: URL and retry helpers

    private func validatedGraphURL(_ value: String) throws -> URL {
        let url = try requireURL(value)
        guard url.scheme == "https",
              url.host?.lowercased() == Self.graphHost else {
            throw MicrosoftGraphError.untrustedDeltaLink
        }
        return url
    }

    private func requireURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else { throw MicrosoftGraphError.invalidURL }
        return url
    }

    private func pathComponent(_ value: String) throws -> String {
        let pathComponentAllowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        guard !value.isEmpty,
              let encoded = value.addingPercentEncoding(withAllowedCharacters: pathComponentAllowed),
              !encoded.isEmpty else {
            throw MicrosoftGraphError.invalidRemoteIdentifier
        }
        return encoded
    }

    private nonisolated static var graphDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private nonisolated static func retryDelay(attempt: Int, retryAfter: String?) -> Double {
        if let retryAfter,
           let serverDelay = Double(retryAfter),
           serverDelay > 0 {
            return min(serverDelay, 60)
        }
        return min(pow(2, Double(attempt)), 8)
    }

    private nonisolated static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return String(message.prefix(280))
    }
}

// MARK: - Error

public enum MicrosoftGraphError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case invalidRemoteIdentifier
    case untrustedDeltaLink
    case missingDeltaLink
    case pageLimitExceeded
    case deltaTokenExpired
    case preconditionFailed
    case retryLimitExceeded
    case httpError(Int, String?)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Microsoft Graph URL"
        case .invalidResponse:
            return "Invalid Microsoft Graph response"
        case .invalidRemoteIdentifier:
            return "Invalid Microsoft remote identifier"
        case .untrustedDeltaLink:
            return "Microsoft delta link has an untrusted host"
        case .missingDeltaLink:
            return "Microsoft Graph did not return a delta link"
        case .pageLimitExceeded:
            return "Microsoft Graph page limit exceeded"
        case .deltaTokenExpired:
            return "Microsoft delta token expired"
        case .preconditionFailed:
            return "Microsoft item changed remotely; refresh before retrying"
        case .retryLimitExceeded:
            return "Microsoft Graph retry limit exceeded"
        case .httpError(let status, let message):
            return message.map { "Microsoft Graph HTTP \(status): \($0)" }
                ?? "Microsoft Graph HTTP \(status)"
        }
    }
}

import Foundation

public protocol TodoistSyncServing: Sendable {
    func sync(
        accessToken: String,
        syncToken: String,
        resourceTypes: [String],
        commands: [TodoistCommand]
    ) async throws -> TodoistSyncResponse
}

public actor TodoistAPI: TodoistSyncServing {
    public static let shared = TodoistAPI()

    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.todoist.com/api/v1/sync")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func sync(
        accessToken: String,
        syncToken: String,
        resourceTypes: [String] = ["items"],
        commands: [TodoistCommand] = []
    ) async throws -> TodoistSyncResponse {
        var fields: [(String, String)] = []
        if !syncToken.isEmpty {
            fields.append(("sync_token", syncToken))
        }
        if !resourceTypes.isEmpty {
            fields.append(("resource_types", try Self.jsonString(resourceTypes)))
        }
        if !commands.isEmpty {
            fields.append(("commands", try Self.jsonString(commands)))
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(fields)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TodoistAPIError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw TodoistAPIError.httpStatus(response.statusCode, Self.errorMessage(from: data))
        }
        do {
            return try JSONDecoder().decode(TodoistSyncResponse.self, from: data)
        } catch {
            throw TodoistAPIError.decoding(error.localizedDescription)
        }
    }

    static func formEncoded(_ fields: [(String, String)]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { name, value in
            URLQueryItem(name: name, value: value)
        }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String ?? object["error_tag"] as? String
    }
}

public enum TodoistAPIError: LocalizedError, Sendable, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Todoist returned an invalid HTTP response"
        case .httpStatus(let status, let detail):
            "Todoist request failed (HTTP \(status))\(detail.map { ": \($0)" } ?? "")"
        case .decoding(let detail):
            "Todoist response could not be decoded: \(detail)"
        }
    }
}

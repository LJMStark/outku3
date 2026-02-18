import Foundation

// MARK: - Network Client

/// 通用网络请求客户端
public actor NetworkClient {
    public static let shared = NetworkClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Public HTTP Methods

    public func get<T: Decodable>(
        url: URL,
        headers: [String: String] = [:],
        responseType: T.Type
    ) async throws -> T {
        try await sendRequest(url: url, method: "GET", headers: headers)
    }

    public func post<T: Decodable, B: Encodable>(
        url: URL,
        headers: [String: String] = [:],
        body: B,
        responseType: T.Type
    ) async throws -> T {
        try await sendRequest(url: url, method: "POST", headers: headers, body: body)
    }

    public func patch<T: Decodable, B: Encodable>(
        url: URL,
        headers: [String: String] = [:],
        body: B,
        responseType: T.Type
    ) async throws -> T {
        try await sendRequest(url: url, method: "PATCH", headers: headers, body: body)
    }

    public func delete(
        url: URL,
        headers: [String: String] = [:]
    ) async throws {
        let _: EmptyResponse = try await sendRequest(url: url, method: "DELETE", headers: headers)
    }

    // MARK: - Core Request

    private func sendRequest<T: Decodable>(
        url: URL,
        method: String,
        headers: [String: String],
        body: (any Encodable)? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Authenticated Request with 401 Retry

    public func authenticatedRequest<T: Decodable & Sendable>(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        responseType: T.Type,
        refreshToken: @Sendable () async throws -> String
    ) async throws -> T {
        do {
            return try await executeRequest(url: url, method: method, headers: headers, body: body, responseType: responseType)
        } catch NetworkError.unauthorized {
            let newToken = try await refreshToken()
            var updatedHeaders = headers
            updatedHeaders["Authorization"] = "Bearer \(newToken)"
            return try await executeRequest(url: url, method: method, headers: updatedHeaders, body: body, responseType: responseType)
        }
    }

    public func authenticatedRequestNoContent(
        url: String,
        method: String = "DELETE",
        headers: [String: String] = [:],
        refreshToken: @Sendable () async throws -> String
    ) async throws {
        let _: EmptyResponse = try await authenticatedRequest(
            url: url,
            method: method,
            headers: headers,
            responseType: EmptyResponse.self,
            refreshToken: refreshToken
        )
    }

    private func executeRequest<T: Decodable>(
        url urlString: String,
        method: String,
        headers: [String: String],
        body: (any Encodable)? = nil,
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidResponse
        }
        return try await sendRequest(url: url, method: method, headers: headers, body: body)
    }

    // MARK: - Validation

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw NetworkError.unauthorized
        case 403:
            throw NetworkError.forbidden
        case 404:
            throw NetworkError.notFound
        case 429:
            throw NetworkError.rateLimited
        case 500...599:
            throw NetworkError.serverError(httpResponse.statusCode)
        default:
            throw NetworkError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - EmptyResponse

private struct EmptyResponse: Decodable {}

// MARK: - AnyEncodable

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        self._encode = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Network Error

public enum NetworkError: LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - please sign in again"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Too many requests - please try again later"
        case .serverError(let code):
            return "Server error (\(code))"
        case .httpError(let code):
            return "HTTP error (\(code))"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        }
    }
}

import Foundation

// MARK: - Notion API

/// Notion API client (read + update task status)
public actor NotionAPI {
    public static let shared = NotionAPI()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://api.notion.com/v1"
    private let apiVersion = "2022-06-28"

    private init() {}

    // MARK: - Search Databases

    /// Search for databases shared with this integration
    public func searchDatabases(accessToken: String) async throws -> [NotionObject] {
        guard let url = URL(string: "\(baseURL)/search") else {
            throw NotionAPIError.invalidURL
        }

        var allResults: [NotionObject] = []
        var cursor: String? = nil
        let maxPages = 10

        for _ in 0..<maxPages {
            let requestBody = NotionSearchRequest(
                filter: NotionSearchFilter(value: "database", property: "object"),
                startCursor: cursor,
                pageSize: 100
            )

            let response: NotionSearchResponse = try await networkClient.post(
                url: url,
                headers: makeHeaders(accessToken),
                body: requestBody,
                responseType: NotionSearchResponse.self
            )

            allResults.append(contentsOf: response.results)
            cursor = response.nextCursor

            if !response.hasMore || cursor == nil {
                break
            }
        }

        return allResults
    }

    // MARK: - Query Database

    /// Query pages (tasks) from a specific database
    public func queryDatabase(
        databaseId: String,
        accessToken: String,
        startCursor: String? = nil
    ) async throws -> NotionQueryResponse {
        guard let url = URL(string: "\(baseURL)/databases/\(databaseId)/query") else {
            throw NotionAPIError.invalidURL
        }

        let requestBody = NotionQueryRequest(
            startCursor: startCursor,
            pageSize: 100
        )

        return try await networkClient.post(
            url: url,
            headers: makeHeaders(accessToken),
            body: requestBody,
            responseType: NotionQueryResponse.self
        )
    }

    /// Fetch all pages from a database with auto-pagination
    public func getAllPages(
        databaseId: String,
        accessToken: String
    ) async throws -> [NotionPage] {
        var allPages: [NotionPage] = []
        var cursor: String? = nil
        let maxPages = 50

        for _ in 0..<maxPages {
            let response = try await queryDatabase(
                databaseId: databaseId,
                accessToken: accessToken,
                startCursor: cursor
            )

            allPages.append(contentsOf: response.results)
            cursor = response.nextCursor

            if !response.hasMore || cursor == nil {
                break
            }
        }

        return allPages
    }

    // MARK: - Update Page

    /// Update a page's checkbox property (mark task as complete/incomplete)
    public func updatePageCheckbox(
        pageId: String,
        propertyName: String,
        checked: Bool,
        accessToken: String
    ) async throws {
        guard let url = URL(string: "\(baseURL)/pages/\(pageId)") else {
            throw NotionAPIError.invalidURL
        }

        let body = NotionUpdatePageRequest(
            properties: [propertyName: NotionUpdatePropertyValue(checkbox: checked)]
        )

        _ = try await networkClient.patch(
            url: url,
            headers: makeHeaders(accessToken),
            body: body,
            responseType: NotionPage.self
        )
    }

    // MARK: - Helpers

    private func makeHeaders(_ accessToken: String) -> [String: String] {
        [
            "Authorization": "Bearer \(accessToken)",
            "Notion-Version": apiVersion,
            "Content-Type": "application/json"
        ]
    }
}

// MARK: - Notion API Error

public enum NotionAPIError: LocalizedError, Sendable {
    case invalidURL
    case databaseNotFound
    case accessDenied
    case noCheckboxProperty

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to construct Notion API URL"
        case .databaseNotFound:
            return "Notion database not found"
        case .accessDenied:
            return "Notion access denied"
        case .noCheckboxProperty:
            return "No checkbox property found in Notion database"
        }
    }
}

import Foundation

// MARK: - Google Calendar API

/// Google Calendar API 客户端（只读）
public actor GoogleCalendarAPI {
    public static let shared = GoogleCalendarAPI()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    private init() {}

    // MARK: - Get Events

    /// 获取日历事件列表
    /// - Parameters:
    ///   - calendarId: 日历 ID，默认为 "primary"
    ///   - timeMin: 开始时间
    ///   - timeMax: 结束时间
    ///   - syncToken: 增量同步 token
    /// - Returns: 事件列表响应
    public func getEvents(
        calendarId: String = "primary",
        timeMin: Date? = nil,
        timeMax: Date? = nil,
        syncToken: String? = nil,
        maxResults: Int = 100
    ) async throws -> GoogleCalendarListResponse {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        var components = URLComponents(string: "\(baseURL)/calendars/\(calendarId)/events")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        if let syncToken = syncToken {
            // 增量同步
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            // 全量获取
            if let timeMin = timeMin {
                queryItems.append(URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)))
            }
            if let timeMax = timeMax {
                queryItems.append(URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)))
            }
        }

        components.queryItems = queryItems

        return try await networkClient.get(
            url: components.url!,
            headers: ["Authorization": "Bearer \(accessToken)"],
            responseType: GoogleCalendarListResponse.self
        )
    }

    /// 获取今日事件
    public func getTodayEvents() async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let response = try await getEvents(
            timeMin: startOfDay,
            timeMax: endOfDay
        )

        return (response.items ?? []).compactMap { CalendarEvent.from(googleEvent: $0) }
    }

    /// 获取本周事件
    public func getWeekEvents() async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!

        let response = try await getEvents(
            timeMin: startOfWeek,
            timeMax: endOfWeek
        )

        return (response.items ?? []).compactMap { CalendarEvent.from(googleEvent: $0) }
    }

    /// 增量同步事件
    /// - Parameter syncToken: 上次同步返回的 token
    /// - Returns: 新的/更新的事件和新的 sync token
    public func syncEvents(syncToken: String) async throws -> (events: [CalendarEvent], newSyncToken: String?) {
        do {
            let response = try await getEvents(syncToken: syncToken)
            let events = (response.items ?? []).compactMap { CalendarEvent.from(googleEvent: $0) }
            return (events, response.nextSyncToken)
        } catch NetworkError.httpError(410) {
            // Sync token 过期，需要全量同步
            throw GoogleCalendarError.syncTokenExpired
        }
    }

    // MARK: - Get Calendar List

    /// 获取用户的日历列表
    public func getCalendarList() async throws -> [GoogleCalendarInfo] {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        let url = URL(string: "\(baseURL)/users/me/calendarList")!

        let response: GoogleCalendarListInfoResponse = try await networkClient.get(
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)"],
            responseType: GoogleCalendarListInfoResponse.self
        )

        return response.items ?? []
    }
}

// MARK: - Google Calendar Error

public enum GoogleCalendarError: LocalizedError, Sendable {
    case syncTokenExpired
    case calendarNotFound
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .syncTokenExpired:
            return "Sync token expired, full sync required"
        case .calendarNotFound:
            return "Calendar not found"
        case .accessDenied:
            return "Calendar access denied"
        }
    }
}

// MARK: - Calendar Info Models

public struct GoogleCalendarInfo: Codable, Sendable {
    public let id: String
    public let summary: String?
    public let primary: Bool?
    public let backgroundColor: String?
    public let foregroundColor: String?
}

public struct GoogleCalendarListInfoResponse: Codable, Sendable {
    public let items: [GoogleCalendarInfo]?
    public let nextPageToken: String?
}

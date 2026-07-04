import Foundation

// MARK: - Google Calendar API

private struct CalendarFetchOutcome: Sendable {
    let calendarId: String
    let events: [CalendarEvent]
    let errorDescription: String?
}

/// Google Calendar API 客户端
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
        maxResults: Int = 100,
        pageToken: String? = nil
    ) async throws -> GoogleCalendarListResponse {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        guard var components = URLComponents(string: "\(baseURL)/calendars/\(encodedCalendarId)/events") else {
            throw GoogleCalendarError.invalidURL
        }
        components.queryItems = makeEventsQueryItems(
            timeMin: timeMin,
            timeMax: timeMax,
            syncToken: syncToken,
            maxResults: maxResults,
            pageToken: pageToken
        )

        guard let url = components.url else {
            throw GoogleCalendarError.invalidURL
        }

        return try await networkClient.get(
            url: url,
            headers: makeAuthorizationHeader(accessToken),
            responseType: GoogleCalendarListResponse.self
        )
    }

    // MARK: - Fetch All Pages

    /// 自动分页获取所有事件
    private func fetchAllPages(
        calendarId: String = "primary",
        timeMin: Date? = nil,
        timeMax: Date? = nil,
        syncToken: String? = nil,
        maxResults: Int = 100
    ) async throws -> GoogleCalendarListResponse {
        var allItems: [GoogleCalendarEvent] = []
        var currentPageToken: String? = nil
        var lastSyncToken: String? = nil
        let maxPages = 50

        for _ in 0..<maxPages {
            let response = try await getEvents(
                calendarId: calendarId,
                timeMin: timeMin,
                timeMax: timeMax,
                syncToken: syncToken,
                maxResults: maxResults,
                pageToken: currentPageToken
            )

            if let items = response.items {
                allItems.append(contentsOf: items)
            }

            lastSyncToken = response.nextSyncToken
            currentPageToken = response.nextPageToken

            if currentPageToken == nil {
                break
            }
        }

        return GoogleCalendarListResponse(
            items: allItems,
            nextPageToken: nil,
            nextSyncToken: lastSyncToken
        )
    }

    /// 获取今日事件
    public func getTodayEvents() async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return try await getEventsAcrossCalendars(timeMin: startOfDay, timeMax: endOfDay)
    }

    /// 获取本周事件
    public func getWeekEvents() async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        return try await getEventsAcrossCalendars(timeMin: startOfWeek, timeMax: endOfWeek)
    }

    // MARK: - Multi Calendar Fetch

    /// 获取多个日历的事件并去重（默认至少包含 primary）
    private func getEventsAcrossCalendars(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] {
        let calendarIds = try await loadTargetCalendarIds()

        var latestByEventId: [String: CalendarEvent] = [:]
        var failures: [String] = []

        await withTaskGroup(of: CalendarFetchOutcome.self) { group in
            for calendarId in calendarIds {
                group.addTask {
                    do {
                        let response = try await self.fetchAllPages(
                            calendarId: calendarId,
                            timeMin: timeMin,
                            timeMax: timeMax
                        )
                        let events = (response.items ?? []).compactMap {
                            CalendarEvent.from(googleEvent: $0, googleCalendarId: calendarId)
                        }
                        return CalendarFetchOutcome(
                            calendarId: calendarId,
                            events: events,
                            errorDescription: nil
                        )
                    } catch {
                        return CalendarFetchOutcome(
                            calendarId: calendarId,
                            events: [],
                            errorDescription: error.localizedDescription
                        )
                    }
                }
            }

            for await outcome in group {
                if let errorDescription = outcome.errorDescription {
                    failures.append("\(outcome.calendarId): \(errorDescription)")
                    continue
                }

                for event in outcome.events {
                    if let existing = latestByEventId[event.id] {
                        if event.lastModified > existing.lastModified {
                            latestByEventId[event.id] = event
                        }
                    } else {
                        latestByEventId[event.id] = event
                    }
                }
            }
        }

        #if DEBUG
        if !failures.isEmpty {
            print("[GoogleCalendarAPI] Calendar fetch partial failures: \(failures.joined(separator: " | "))")
        }
        print("[GoogleCalendarAPI] Calendar fetch success=\(calendarIds.count - failures.count)/\(calendarIds.count), events=\(latestByEventId.count)")
        #endif

        // 任一日历拉取失败就整体抛错，而不是只在全部失败时抛。原先部分失败会静默返回成功日历的事件，
        // 上层用 nonGoogle + syncedEvents 整组替换 → 失败日历的事件凭空消失且整轮报 Success。抛错后走
        // runSyncStep 的 .failure：保留上轮 Google 事件（不丢，仅本轮不刷新），失败经 warnings 上报到
        // remoteSyncErrors（齿轮红点 + Settings 行内）。瞬时失败下轮恢复即重新拉全。
        if !failures.isEmpty {
            throw GoogleCalendarError.calendarFetchFailed(failures.joined(separator: " | "))
        }

        return latestByEventId.values.sorted { $0.startTime < $1.startTime }
    }

    private func loadTargetCalendarIds() async throws -> [String] {
        // 日历列表拉取失败不能静默收窄为仅 primary：上层对 Google 事件是整组替换，收窄后
        // 非主日历事件会本轮凭空消失且整轮报 Success。与上面"任一日历拉取失败就整体抛错"
        // 同一策略——抛错走 runSyncStep 的 .failure：保留上轮事件，错误经 warnings 上报。
        //
        // 例外——403 scope 不足是 by-design，不是故障：App 登录只申请 calendar.events（无
        // calendar.readonly，见 GoogleSignInService），而 calendarList 端点不被 events scope
        // 覆盖，因此该调用自首日起恒 403。此前被静默吞掉；263e439 浮出后把这个档位的正常
        // 现象误报成了用户可见 warning（2026-07-04 硬件团队反馈）。events-only 档位的正确
        // 行为就是 primary-only 同步；要解锁多日历，先补 readonly scope + 引导用户重连。
        let calendars: [GoogleCalendarInfo]
        do {
            calendars = try await getCalendarList()
        } catch let NetworkError.forbiddenWithMessage(message)
            where message.localizedCaseInsensitiveContains("insufficient") {
            // 只对"scope 不足"这一种 403 降级——其他 403（配额、封禁等）照抛走 warnings，
            // 避免把真实故障也吞成 primary-only（Codex review P2, 2026-07-04）。
            #if DEBUG
            print("[GoogleCalendarAPI] calendarList 403 (events-only scope) — primary-only by design")
            #endif
            return ["primary"]
        }
        let selectedIds = calendars
            .filter { ($0.selected ?? true) && !($0.hidden ?? false) }
            .map(\.id)

        let allIds = selectedIds.isEmpty ? calendars.map(\.id) : selectedIds
        let uniqueIds = orderedUniqueCalendarIDs(from: allIds)

        guard !uniqueIds.isEmpty else { return ["primary"] }
        if uniqueIds.contains("primary") { return uniqueIds }
        return ["primary"] + uniqueIds
    }

    /// 增量同步事件
    /// - Parameter syncToken: 上次同步返回的 token
    /// - Returns: 新的/更新的事件和新的 sync token
    public func syncEvents(syncToken: String) async throws -> (events: [CalendarEvent], newSyncToken: String?) {
        do {
            let response = try await fetchAllPages(syncToken: syncToken)
            let events = (response.items ?? []).compactMap { CalendarEvent.from(googleEvent: $0) }
            return (events, response.nextSyncToken)
        } catch NetworkError.httpError(410) {
            // Sync token 过期，需要全量同步
            throw GoogleCalendarError.syncTokenExpired
        }
    }

    // MARK: - Patch Event

    public func patchEvent(
        calendarId: String,
        eventId: String,
        title: String?,
        startTime: Date?,
        endTime: Date?,
        isAllDay: Bool = false,
        location: String?,
        description: String?
    ) async throws -> CalendarEvent {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        guard let url = URL(string: "\(baseURL)/calendars/\(encodedCalendarId)/events/\(encodedEventId)") else {
            throw GoogleCalendarError.invalidURL
        }

        let body = GoogleCalendarEventPatchRequest(
            summary: title,
            location: location,
            description: description,
            start: startTime.map { isAllDay ? .allDay($0) : .timed($0) },
            end: endTime.map { isAllDay ? .allDay($0) : .timed($0) }
        )

        let event: GoogleCalendarEvent = try await networkClient.patch(
            url: url,
            headers: makeAuthorizationHeader(accessToken),
            body: body,
            responseType: GoogleCalendarEvent.self
        )

        guard let mappedEvent = CalendarEvent.from(
            googleEvent: event,
            googleCalendarId: calendarId
        ) else {
            throw NetworkError.decodingError("Patched Google event could not be mapped")
        }

        return mappedEvent
    }

    // MARK: - Get Calendar List

    /// 获取用户的日历列表
    public func getCalendarList() async throws -> [GoogleCalendarInfo] {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        guard let url = URL(string: "\(baseURL)/users/me/calendarList") else {
            throw GoogleCalendarError.invalidURL
        }

        let response: GoogleCalendarListInfoResponse = try await networkClient.get(
            url: url,
            headers: makeAuthorizationHeader(accessToken),
            responseType: GoogleCalendarListInfoResponse.self
        )

        return response.items ?? []
    }

    private func makeAuthorizationHeader(_ accessToken: String) -> [String: String] {
        ["Authorization": "Bearer \(accessToken)"]
    }

    private func makeEventsQueryItems(
        timeMin: Date?,
        timeMax: Date?,
        syncToken: String?,
        maxResults: Int,
        pageToken: String?
    ) -> [URLQueryItem] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        if let syncToken {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
            return queryItems
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        if let timeMin {
            queryItems.append(URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)))
        }
        if let timeMax {
            queryItems.append(URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)))
        }

        return queryItems
    }

    private func orderedUniqueCalendarIDs(from ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for id in ids where !id.isEmpty {
            if seen.insert(id).inserted {
                result.append(id)
            }
        }

        return result
    }
}

// MARK: - Google Calendar Error

public enum GoogleCalendarError: LocalizedError, Sendable {
    case syncTokenExpired
    case calendarNotFound
    case accessDenied
    case calendarFetchFailed(String)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .syncTokenExpired:
            return "Sync token expired, full sync required"
        case .calendarNotFound:
            return "Calendar not found"
        case .accessDenied:
            return "Calendar access denied"
        case .calendarFetchFailed(let details):
            return "Failed to fetch calendars: \(details)"
        case .invalidURL:
            return "Failed to construct calendar API URL"
        }
    }
}

// MARK: - Calendar Info Models

public struct GoogleCalendarInfo: Codable, Sendable {
    public let id: String
    public let summary: String?
    public let primary: Bool?
    public let selected: Bool?
    public let hidden: Bool?
    public let backgroundColor: String?
    public let foregroundColor: String?
}

public struct GoogleCalendarListInfoResponse: Codable, Sendable {
    public let items: [GoogleCalendarInfo]?
    public let nextPageToken: String?
}

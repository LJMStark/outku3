import Foundation
import os

public enum AppSecrets {
    private struct Storage: Sendable {
        var supabaseURL: String?
        var supabaseAnonKey: String?
        var openRouterAPIKey: String?
        var bleSharedSecret: String?
        var deepFocusFeatureEnabled: Bool
        var notionClientId: String?
        var taskadeClientId: String?
        /// Optional AI base URL override (e.g. an OpenAI-compatible gateway). nil → OpenRouter default.
        var openAIBaseURL: String?
        /// Optional chat model override. nil → `OpenAIService.defaultChatModelID` OpenRouter default.
        var chatModelID: String?
        /// Optional fallback (OpenRouter) bearer key — used to fail over to OpenRouter when the
        /// configured primary provider errors. nil → no cross-provider fallback. See OpenAIService.
        var fallbackAPIKey: String?
    }

    private static let lock = OSAllocatedUnfairLock(
        initialState: Storage(deepFocusFeatureEnabled: false)
    )

    public static func configure(
        supabaseURL: String?,
        supabaseAnonKey: String?,
        openRouterAPIKey: String?,
        bleSharedSecret: String?,
        deepFocusFeatureEnabled: Bool = false,
        notionClientId: String? = nil,
        taskadeClientId: String? = nil,
        openAIBaseURL: String? = nil,
        chatModelID: String? = nil,
        fallbackAPIKey: String? = nil
    ) {
        lock.withLock { storage in
            storage.supabaseURL = normalizeURL(supabaseURL)
            storage.supabaseAnonKey = normalize(supabaseAnonKey)
            storage.openRouterAPIKey = normalize(openRouterAPIKey)
            storage.bleSharedSecret = normalize(bleSharedSecret)
            storage.deepFocusFeatureEnabled = deepFocusFeatureEnabled
            storage.notionClientId = normalize(notionClientId)
            storage.taskadeClientId = normalize(taskadeClientId)
            storage.openAIBaseURL = normalizeURL(openAIBaseURL)
            storage.chatModelID = normalize(chatModelID)
            storage.fallbackAPIKey = normalize(fallbackAPIKey)
        }
    }

    public static var supabaseConfig: (url: String, anonKey: String)? {
        lock.withLock { storage in
            guard let url = storage.supabaseURL, let key = storage.supabaseAnonKey else { return nil }
            return (url, key)
        }
    }

    public static var openRouterAPIKey: String? {
        lock.withLock { $0.openRouterAPIKey }
    }

    public static var bleSharedSecret: String? {
        lock.withLock { $0.bleSharedSecret }
    }

    public static var deepFocusFeatureEnabled: Bool {
        lock.withLock { $0.deepFocusFeatureEnabled }
    }

    public static var notionClientId: String? {
        lock.withLock { $0.notionClientId }
    }

    public static var taskadeClientId: String? {
        lock.withLock { $0.taskadeClientId }
    }

    /// Optional AI base URL override; nil → `OpenAIService` falls back to the OpenRouter default.
    public static var openAIBaseURL: String? {
        lock.withLock { $0.openAIBaseURL }
    }

    /// Optional chat model override; nil → `OpenAIService.defaultChatModelID` OpenRouter default.
    public static var chatModelID: String? {
        lock.withLock { $0.chatModelID }
    }

    /// Optional fallback (OpenRouter) bearer key; nil → no cross-provider fallback.
    public static var fallbackAPIKey: String? {
        lock.withLock { $0.fallbackAPIKey }
    }

    private static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.contains("YOUR_") || trimmed.hasPrefix("$(") {
            return nil
        }
        return trimmed
    }

    /// Stricter normalization for URL secrets: rejects values whose `URL.host`
    /// is nil/empty so callers never receive a half-URL like `"https:"`.
    private static func normalizeURL(_ value: String?) -> String? {
        guard let trimmed = normalize(value) else { return nil }
        guard let url = URL(string: trimmed),
              let host = url.host,
              !host.isEmpty else {
            #if DEBUG
            print("[AppSecrets] Rejected URL with no host: \(trimmed)")
            #endif
            return nil
        }
        return trimmed
    }
}

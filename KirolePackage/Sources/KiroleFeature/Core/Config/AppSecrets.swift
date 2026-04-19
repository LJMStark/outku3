import Foundation

public enum AppSecrets {
    private struct Storage {
        var supabaseURL: String?
        var supabaseAnonKey: String?
        var openRouterAPIKey: String?
        var bleSharedSecret: String?
        var deepFocusFeatureEnabled: Bool
        var notionClientId: String?
        var notionClientSecret: String?
        var taskadeClientId: String?
        var taskadeClientSecret: String?
    }

    private nonisolated(unsafe) static var storage = Storage(deepFocusFeatureEnabled: false)
    private static let queue = DispatchQueue(label: "com.kirole.app.secrets", attributes: .concurrent)

    public static func configure(
        supabaseURL: String?,
        supabaseAnonKey: String?,
        openRouterAPIKey: String?,
        bleSharedSecret: String?,
        deepFocusFeatureEnabled: Bool = false,
        notionClientId: String? = nil,
        notionClientSecret: String? = nil,
        taskadeClientId: String? = nil,
        taskadeClientSecret: String? = nil
    ) {
        queue.sync(flags: .barrier) {
            storage.supabaseURL = normalizeURL(supabaseURL)
            storage.supabaseAnonKey = normalize(supabaseAnonKey)
            storage.openRouterAPIKey = normalize(openRouterAPIKey)
            storage.bleSharedSecret = normalize(bleSharedSecret)
            storage.deepFocusFeatureEnabled = deepFocusFeatureEnabled
            storage.notionClientId = normalize(notionClientId)
            storage.notionClientSecret = normalize(notionClientSecret)
            storage.taskadeClientId = normalize(taskadeClientId)
            storage.taskadeClientSecret = normalize(taskadeClientSecret)
        }
    }

    public static var supabaseConfig: (url: String, anonKey: String)? {
        queue.sync {
            guard let url = storage.supabaseURL, let key = storage.supabaseAnonKey else { return nil }
            return (url, key)
        }
    }

    public static var openRouterAPIKey: String? {
        queue.sync { storage.openRouterAPIKey }
    }

    public static var bleSharedSecret: String? {
        queue.sync { storage.bleSharedSecret }
    }

    public static var deepFocusFeatureEnabled: Bool {
        queue.sync { storage.deepFocusFeatureEnabled }
    }

    public static var notionClientId: String? {
        queue.sync { storage.notionClientId }
    }

    public static var notionClientSecret: String? {
        queue.sync { storage.notionClientSecret }
    }

    public static var taskadeClientId: String? {
        queue.sync { storage.taskadeClientId }
    }

    public static var taskadeClientSecret: String? {
        queue.sync { storage.taskadeClientSecret }
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
    /// Required because xcconfig's `//` comment rule has, in the past, silently
    /// truncated `https://x.supabase.co` to `https:` and crashed supabase-swift
    /// on `supabaseURL.host!`.
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

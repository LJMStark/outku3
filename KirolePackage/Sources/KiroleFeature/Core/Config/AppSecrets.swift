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
        taskadeClientId: String? = nil
    ) {
        lock.withLock { storage in
            storage.supabaseURL = normalizeURL(supabaseURL)
            storage.supabaseAnonKey = normalize(supabaseAnonKey)
            storage.openRouterAPIKey = normalize(openRouterAPIKey)
            storage.bleSharedSecret = normalize(bleSharedSecret)
            storage.deepFocusFeatureEnabled = deepFocusFeatureEnabled
            storage.notionClientId = normalize(notionClientId)
            storage.taskadeClientId = normalize(taskadeClientId)
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

import Foundation

public enum AppSecrets {
    private struct Storage {
        var supabaseURL: String?
        var supabaseAnonKey: String?
        var openRouterAPIKey: String?
        var bleSharedSecret: String?
    }

    private nonisolated(unsafe) static var storage = Storage()
    private static let queue = DispatchQueue(label: "com.kirole.app.secrets", attributes: .concurrent)

    public static func configure(
        supabaseURL: String?,
        supabaseAnonKey: String?,
        openRouterAPIKey: String?,
        bleSharedSecret: String?
    ) {
        queue.sync(flags: .barrier) {
            storage.supabaseURL = normalize(supabaseURL)
            storage.supabaseAnonKey = normalize(supabaseAnonKey)
            storage.openRouterAPIKey = normalize(openRouterAPIKey)
            storage.bleSharedSecret = normalize(bleSharedSecret)
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

    private static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.contains("YOUR_") || trimmed.hasPrefix("$(") {
            return nil
        }
        return trimmed
    }
}

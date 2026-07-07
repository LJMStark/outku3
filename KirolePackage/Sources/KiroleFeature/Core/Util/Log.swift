import OSLog

/// Unified logger for KiroleFeature.
///
/// Usage:
///   Log.ble.debug("Connected to \(peripheralId, privacy: .private)")
///   Log.ai.error("Prompt failed: \(error)")
///
/// All subsystem logs respect .privacy(.private) for sensitive fields so that
/// Instruments / Console captures them only on development builds.
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.kirole.app"

    public static let ble       = Logger(subsystem: subsystem, category: "BLE")
    public static let ai        = Logger(subsystem: subsystem, category: "AI")
    public static let sync      = Logger(subsystem: subsystem, category: "Sync")
    public static let auth      = Logger(subsystem: subsystem, category: "Auth")
    public static let storage   = Logger(subsystem: subsystem, category: "Storage")
    public static let ui        = Logger(subsystem: subsystem, category: "UI")
    public static let pet       = Logger(subsystem: subsystem, category: "Pet")
    public static let network   = Logger(subsystem: subsystem, category: "Network")
    public static let companion = Logger(subsystem: subsystem, category: "Companion")
    public static let config    = Logger(subsystem: subsystem, category: "Config")
    public static let weather   = Logger(subsystem: subsystem, category: "Weather")
}

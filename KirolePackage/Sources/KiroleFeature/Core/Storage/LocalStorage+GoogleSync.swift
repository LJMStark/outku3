import Foundation

extension LocalStorage {
    /// Removes every account-scoped Google sync artifact and verifies that neither a live nor a
    /// quarantined copy remains. Google outbox entries predate account ownership, so retaining
    /// either file across disconnect or a fresh authorization could replay account A's command
    /// against account B.
    public func resetGoogleSyncState() throws {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileNames = [
            "outbox.json",
            "outbox.json.corrupt",
            "google_sync_metadata.json",
            "google_sync_metadata.json.corrupt",
        ]

        for fileName in fileNames {
            let url = documentsDirectory.appendingPathComponent(fileName, isDirectory: false)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        guard fileNames.allSatisfy({ fileName in
            let url = documentsDirectory.appendingPathComponent(fileName, isDirectory: false)
            return !fileManager.fileExists(atPath: url.path)
        }) else {
            throw GoogleSyncStateCleanupError.verificationFailed
        }
    }
}

enum GoogleSyncStateCleanupError: LocalizedError, Sendable {
    case verificationFailed

    var errorDescription: String? {
        "Google sync metadata or outbox could not be removed"
    }
}

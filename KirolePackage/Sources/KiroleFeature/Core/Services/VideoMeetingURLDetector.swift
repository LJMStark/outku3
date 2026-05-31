import Foundation

// MARK: - Video Meeting URL Detector

/// Scans text for known video-conferencing URLs using NSDataDetector.
/// Recognized hosts: zoom.us, meet.google.com, teams.microsoft.com, teams.live.com, meet.lync.com
enum VideoMeetingURLDetector {

    private static let knownDomains: [String] = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "meet.lync.com"
    ]

    /// Returns the first video-meeting URL found in `text`, or nil if none found.
    static func detect(in text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches {
            guard let url = match.url else { continue }
            if isVideoMeetingURL(url) { return url }
        }
        return nil
    }

    /// Returns the first video-meeting URL from description, then location. Returns nil if none.
    static func detect(description: String?, location: String?) -> URL? {
        detect(in: description) ?? detect(in: location)
    }

    /// Returns true if `url` is a known video-meeting domain or a subdomain of one.
    static func isVideoMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return knownDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
}

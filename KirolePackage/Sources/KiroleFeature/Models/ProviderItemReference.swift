import Foundation

/// Provider-owned identity and concurrency metadata kept outside the BLE wire contract.
/// Every remote item is namespaced by provider, account, container and item so opaque IDs from
/// different accounts or services cannot collide.
public struct ProviderItemReference: Sendable, Codable, Hashable {
    public var provider: ExternalProvider
    public var accountID: String
    public var containerID: String?
    public var itemID: String
    public var etag: String?
    public var remoteStatus: String?
    public var previousRemoteStatus: String?
    public var allowsContentModifications: Bool

    public init(
        provider: ExternalProvider,
        accountID: String,
        containerID: String? = nil,
        itemID: String,
        etag: String? = nil,
        remoteStatus: String? = nil,
        previousRemoteStatus: String? = nil,
        allowsContentModifications: Bool = true
    ) {
        self.provider = provider
        self.accountID = accountID
        self.containerID = containerID
        self.itemID = itemID
        self.etag = etag
        self.remoteStatus = remoteStatus
        self.previousRemoteStatus = previousRemoteStatus
        self.allowsContentModifications = allowsContentModifications
    }

    public var stableLocalID: String {
        let segments = [
            "default",
            accountID,
            containerID ?? "default",
            itemID,
        ]
        return provider.rawValue + ":" + segments.map(Self.lengthPrefixed).joined(separator: ":")
    }

    private static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}

public enum ExternalProvider: String, Sendable, Codable, CaseIterable {
    case appleCalendar
    case appleReminders
    case googleCalendar
    case googleTasks
}

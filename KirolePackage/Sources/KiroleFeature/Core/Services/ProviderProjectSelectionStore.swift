import Foundation

public enum ProviderProjectSelectionKey: String, Sendable {
    case todoist
    case tickTickInternational
    case didaChina

    public static func tickTick(_ region: TickTickRegion) -> Self {
        switch region {
        case .international: .tickTickInternational
        case .china: .didaChina
        }
    }
}

/// Actor-isolated user choice for remote projects. A missing preference intentionally resolves
/// to an empty set so a newly authorized provider never imports every project without consent.
public actor ProviderProjectSelectionStore {
    public static let shared = ProviderProjectSelectionStore()

    private let defaults: UserDefaults
    private let keyPrefix = "integrations.selectedProjects."

    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func selectedProjectIDs(for key: ProviderProjectSelectionKey) -> Set<String> {
        Set(defaults.stringArray(forKey: keyPrefix + key.rawValue) ?? [])
    }

    public func save(_ identifiers: Set<String>, for key: ProviderProjectSelectionKey) {
        defaults.set(identifiers.sorted(), forKey: keyPrefix + key.rawValue)
    }

    public func clear(_ key: ProviderProjectSelectionKey) {
        defaults.removeObject(forKey: keyPrefix + key.rawValue)
    }
}

public struct ProviderProjectDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

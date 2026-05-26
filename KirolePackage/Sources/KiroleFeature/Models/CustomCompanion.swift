import Foundation

// MARK: - Custom Companion

/// User-created companion (4th option alongside Joy/Silas/Nova).
/// Inspired by Inku's avatar+persona model: free-form image upload + structured persona dials.
public struct CustomCompanion: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var relationship: CompanionRelationship
    public var personaVoice: CompanionPersonaVoice
    public var roastModeEnabled: Bool
    public var avatarPreviewFileName: String
    public var avatarPixelsFileName: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        relationship: CompanionRelationship,
        personaVoice: CompanionPersonaVoice,
        roastModeEnabled: Bool = false,
        avatarPreviewFileName: String,
        avatarPixelsFileName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.personaVoice = personaVoice
        self.roastModeEnabled = roastModeEnabled
        self.avatarPreviewFileName = avatarPreviewFileName
        self.avatarPixelsFileName = avatarPixelsFileName
        self.createdAt = createdAt
    }
}

// MARK: - Companion Relationship

public enum CompanionRelationship: String, Sendable, Codable, CaseIterable {
    case pet = "Pet"
    case child = "Child"
    case partner = "Partner"
    case friend = "Friend"
    case mentor = "Mentor"
    case selfDigitalTwin = "Self"
    case other = "Other"

    public var displayName: String { rawValue }

    public var iconName: String {
        switch self {
        case .pet: return "pawprint.fill"
        case .child: return "figure.child"
        case .partner: return "heart.fill"
        case .friend: return "person.2.fill"
        case .mentor: return "graduationcap.fill"
        case .selfDigitalTwin: return "person.fill"
        case .other: return "sparkle"
        }
    }

    /// Prompt fragment describing how the companion relates to the user.
    /// Written tight so it composes with the persona voice without ballooning the system prompt.
    public var promptDescription: String {
        switch self {
        case .pet:
            return "You are the user's beloved pet companion, loyal and tuned to their daily rhythm."
        case .child:
            return "You speak with the wonder and unfiltered honesty of a child the user adores."
        case .partner:
            return "You share an intimate bond with the user — speak with the ease of someone who knows them deeply."
        case .friend:
            return "You are the user's close friend — casual, supportive, never preachy."
        case .mentor:
            return "You are a mentor the user respects — wise, succinct, never condescending."
        case .selfDigitalTwin:
            return "You are the user's reflective self — speak as their inner voice, calm and self-aware."
        case .other:
            return "You are a companion the user has invited into their day."
        }
    }
}

// MARK: - Persona Voice

/// Structured voice presets (no free-form prompt input — keeps generation quality stable
/// and removes most prompt-injection surface area).
public enum CompanionPersonaVoice: String, Sendable, Codable, CaseIterable {
    case companion = "Companion"
    case challenger = "Challenger"
    case zen = "Zen"
    case playful = "Playful"

    public var displayName: String { rawValue }

    public var iconName: String {
        switch self {
        case .companion: return "heart.text.square"
        case .challenger: return "flame.fill"
        case .zen: return "leaf.fill"
        case .playful: return "sparkles"
        }
    }

    public var shortDescription: String {
        switch self {
        case .companion: return "Warm presence, gentle encouragement"
        case .challenger: return "Direct nudges, raises the bar"
        case .zen: return "Quiet, grounded, spacious"
        case .playful: return "Light, witty, slightly mischievous"
        }
    }

    public var promptDescription: String {
        switch self {
        case .companion:
            return "Voice: warm, attentive, gently encouraging. Notice small wins. Never rush the user."
        case .challenger:
            return "Voice: direct, confident, raises the bar without scolding. Ask one sharp question when it helps."
        case .zen:
            return "Voice: quiet, spacious, grounded. Short sentences. Leave room for the user to breathe."
        case .playful:
            return "Voice: light, witty, a little mischievous. Tease with affection, never sarcasm that bites."
        }
    }
}

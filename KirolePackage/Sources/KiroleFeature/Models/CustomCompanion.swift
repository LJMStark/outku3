import Foundation

// MARK: - Custom Companion

/// User-created companion (4th option alongside Joy/Silas/Nova).
/// Inspired by Kindroid's multi-dimensional persona model: structured dials + backstory + boundary.
public struct CustomCompanion: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var relationship: CompanionRelationship
    public var personaVoice: CompanionPersonaVoice

    // MARK: Kindroid-style persona dimensions (0.0 – 1.0)
    /// How frequently the companion asks questions and explores ideas. 0 = reserved, 1 = highly curious.
    public var curiosityLevel: Double
    /// How much wit and levity the companion brings. 0 = earnest, 1 = playfully witty.
    public var humorLevel: Double
    /// How directly the companion holds the user to standards. 0 = gentle, 1 = firm accountability.
    public var strictnessLevel: Double
    /// Free-form story describing the companion's history, personality, and quirks.
    public var backstory: String
    /// Free-form topic boundary, e.g. "feel free to tease procrastination, but skip work stress".
    /// Supersedes roastModeEnabled — richer and safer than a boolean toggle.
    public var sensitiveBoundary: String

    /// Kept for JSON backward-compatibility. No longer surfaced in the creation UI;
    /// sensitiveBoundary carries intent for new companions.
    public var roastModeEnabled: Bool

    public var avatarPreviewFileName: String
    public var avatarPixelsFileName: String
    public var createdAt: Date
    /// Bumped on every mutation that affects prompt assembly.
    /// Cache fingerprints reference `id + updatedAt` so any field change invalidates
    /// downstream caches automatically.
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        relationship: CompanionRelationship,
        personaVoice: CompanionPersonaVoice,
        curiosityLevel: Double = 0.5,
        humorLevel: Double = 0.5,
        strictnessLevel: Double = 0.3,
        backstory: String = "",
        sensitiveBoundary: String = "",
        roastModeEnabled: Bool = false,
        avatarPreviewFileName: String,
        avatarPixelsFileName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.personaVoice = personaVoice
        self.curiosityLevel = curiosityLevel
        self.humorLevel = humorLevel
        self.strictnessLevel = strictnessLevel
        self.backstory = backstory
        self.sensitiveBoundary = sensitiveBoundary
        self.roastModeEnabled = roastModeEnabled
        self.avatarPreviewFileName = avatarPreviewFileName
        self.avatarPixelsFileName = avatarPixelsFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CustomCompanion {
    /// Decoder tolerates pre-Kindroid JSON (missing sliders / backstory / sensitiveBoundary)
    /// and pre-updatedAt JSON. All new fields default gracefully so existing companions
    /// continue to load without any migration step.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.relationship = try container.decode(CompanionRelationship.self, forKey: .relationship)
        self.personaVoice = try container.decode(CompanionPersonaVoice.self, forKey: .personaVoice)
        self.curiosityLevel = try container.decodeIfPresent(Double.self, forKey: .curiosityLevel) ?? 0.5
        self.humorLevel = try container.decodeIfPresent(Double.self, forKey: .humorLevel) ?? 0.5
        self.strictnessLevel = try container.decodeIfPresent(Double.self, forKey: .strictnessLevel) ?? 0.3
        self.backstory = try container.decodeIfPresent(String.self, forKey: .backstory) ?? ""
        self.sensitiveBoundary = try container.decodeIfPresent(String.self, forKey: .sensitiveBoundary) ?? ""
        self.roastModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .roastModeEnabled) ?? false
        self.avatarPreviewFileName = try container.decode(String.self, forKey: .avatarPreviewFileName)
        self.avatarPixelsFileName = try container.decode(String.self, forKey: .avatarPixelsFileName)
        let created = try container.decode(Date.self, forKey: .createdAt)
        self.createdAt = created
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
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

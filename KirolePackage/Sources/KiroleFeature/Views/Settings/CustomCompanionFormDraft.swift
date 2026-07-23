import Foundation

/// Pure form state shared by create and edit. Identity-bearing fields remain on the
/// original `CustomCompanion`, so editing can't accidentally create a new identity.
struct CustomCompanionFormDraft: Equatable, Sendable {
    var name: String
    var relationship: CompanionRelationship
    var personaVoice: CompanionPersonaVoice
    var customPrompt: String
    var curiosityLevel: Double
    var humorLevel: Double
    var strictnessLevel: Double
    var backstory: String
    var sensitiveBoundary: String

    init(companion: CustomCompanion? = nil) {
        name = companion?.name ?? ""
        relationship = companion?.relationship ?? .pet
        personaVoice = companion?.personaVoice ?? .companion
        customPrompt = companion?.customPrompt ?? ""
        curiosityLevel = companion?.curiosityLevel ?? 0.5
        humorLevel = companion?.humorLevel ?? 0.5
        strictnessLevel = companion?.strictnessLevel ?? 0.3
        backstory = companion?.backstory ?? ""
        sensitiveBoundary = companion?.sensitiveBoundary ?? ""
    }

    func updating(_ companion: CustomCompanion, now: Date = Date()) -> CustomCompanion {
        var updated = companion
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.relationship = relationship
        updated.personaVoice = personaVoice
        updated.customPrompt = personaVoice == .customPrompt
            ? customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        updated.curiosityLevel = curiosityLevel
        updated.humorLevel = humorLevel
        updated.strictnessLevel = strictnessLevel
        updated.backstory = backstory
        updated.sensitiveBoundary = sensitiveBoundary
        updated.updatedAt = now
        return updated
    }
}

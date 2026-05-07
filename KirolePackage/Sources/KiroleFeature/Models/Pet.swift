import Foundation

public struct Pet: Sendable, Codable {
    public var name: String
    public var pronouns: PetPronouns
    public var adventuresCount: Int
    public var age: Int // in days
    public var status: PetStatus
    public var mood: PetMood
    public var scene: PetScene
    public var lastInteraction: Date
    public var points: Int // accumulated points from completing tasks

    public init(
        name: String = "Baby Waffle",
        pronouns: PetPronouns = .theyThem,
        adventuresCount: Int = 0,
        age: Int = 1,
        status: PetStatus = .happy,
        mood: PetMood = .happy,
        scene: PetScene = .indoor,
        lastInteraction: Date = Date(),
        points: Int = 0
    ) {
        self.name = name
        self.pronouns = pronouns
        self.adventuresCount = adventuresCount
        self.age = age
        self.status = status
        self.mood = mood
        self.scene = scene
        self.lastInteraction = lastInteraction
        self.points = points
    }
}

public enum PetMood: String, Codable, Sendable, CaseIterable {
    case happy = "Happy"
    case excited = "Excited"
    case focused = "Focused"
    case sleepy = "Sleepy"
    case missing = "Missing You"
}

public enum PetScene: String, Codable, Sendable, CaseIterable {
    case indoor = "Indoor"
    case outdoor = "Outdoor"
    case night = "Night"
    case work = "Work"
}

public enum PetPronouns: String, CaseIterable, Sendable, Codable {
    case heHim = "He/Him"
    case sheHer = "She/Her"
    case theyThem = "They/Them"
}

public enum PetStatus: String, Sendable, Codable {
    case happy = "Happy"
    case content = "Content"
    case sleepy = "Sleepy"
    case hungry = "Hungry"
    case excited = "Excited"
}

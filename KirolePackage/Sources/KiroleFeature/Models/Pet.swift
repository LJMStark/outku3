import Foundation

public struct Pet: Sendable, Codable {
    public var name: String
    public var pronouns: PetPronouns
    public var adventuresCount: Int
    public var age: Int // in days
    public var status: PetStatus
    public var mood: PetMood
    public var scene: PetScene
    public var stage: PetStage
    public var progress: Double // 0.0 to 1.0
    public var weight: Double // in grams
    public var height: Double // in cm
    public var tailLength: Double // in cm
    public var currentForm: PetForm
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
        stage: PetStage = .baby,
        progress: Double = 0.0,
        weight: Double = 50,
        height: Double = 5,
        tailLength: Double = 2,
        currentForm: PetForm = .cat,
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
        self.stage = stage
        self.progress = progress
        self.weight = weight
        self.height = height
        self.tailLength = tailLength
        self.currentForm = currentForm
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

public enum PetStage: String, Sendable, Codable {
    case baby = "Baby"
    case child = "Child"
    case teen = "Teen"
    case adult = "Adult"
    case elder = "Elder"

    public var nextStage: PetStage? {
        switch self {
        case .baby: return .child
        case .child: return .teen
        case .teen: return .adult
        case .adult: return .elder
        case .elder: return nil
        }
    }
}

public enum PetForm: String, CaseIterable, Sendable, Codable {
    case cat = "Cat"
    case dog = "Dog"
    case bunny = "Bunny"
    case bird = "Bird"
    case dragon = "Dragon"

    public var iconName: String {
        switch self {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .bunny: return "hare.fill"
        case .bird: return "bird.fill"
        case .dragon: return "flame.fill"
        }
    }

    public var imageName: String {
        switch self {
        case .cat: return "tiko_mushroom"
        case .dog: return "tiko_dog"
        case .bunny: return "tiko_bunny"
        case .bird: return "tiko_bird"
        case .dragon: return "tiko_dragon"
        }
    }
}

import Foundation

// MARK: - Pet State Service

public actor PetStateService {
    public static let shared = PetStateService()

    private init() {}

    // MARK: - Calculate Mood

    public func calculateMood(
        lastInteraction: Date,
        tasksCompletedToday: Int,
        totalTasksToday: Int,
        currentTime: Date = Date()
    ) -> PetMood {
        let calendar = Calendar.current

        if calendar.isSleepyTime(currentTime) {
            return .sleepy
        }

        let hoursSinceInteraction = currentTime.timeIntervalSince(lastInteraction) / 3600
        if hoursSinceInteraction > 24 {
            return .missing
        }

        if totalTasksToday > 0 {
            let completionRate = Double(tasksCompletedToday) / Double(totalTasksToday)
            if completionRate >= 0.8 {
                return .excited
            }
        }

        if calendar.isWorkHours(currentTime) && totalTasksToday > 0 && tasksCompletedToday < totalTasksToday {
            return .focused
        }

        return .happy
    }

    // MARK: - Calculate Scene

    public func calculateScene(
        currentTime: Date = Date(),
        hasTasks: Bool
    ) -> PetScene {
        let calendar = Calendar.current

        if calendar.isNightTime(currentTime) {
            return .night
        }

        if calendar.isWeekend(currentTime) {
            return .outdoor
        }

        if calendar.isWorkHours(currentTime) && hasTasks {
            return .work
        }

        return .indoor
    }

    // MARK: - Update Pet State

    public func updatePetState(
        pet: Pet,
        tasksCompletedToday: Int,
        totalTasksToday: Int
    ) -> Pet {
        var updatedPet = pet
        let now = Date()

        updatedPet.mood = calculateMood(
            lastInteraction: pet.lastInteraction,
            tasksCompletedToday: tasksCompletedToday,
            totalTasksToday: totalTasksToday,
            currentTime: now
        )

        updatedPet.scene = calculateScene(
            currentTime: now,
            hasTasks: totalTasksToday > tasksCompletedToday
        )

        updatedPet.lastInteraction = now

        return updatedPet
    }

    // MARK: - Calculate Progress

    public func calculateProgress(
        currentProgress: Double,
        taskCompleted: Bool,
        streakDays: Int
    ) -> Double {
        guard taskCompleted else { return currentProgress }

        var progress = currentProgress + 0.02

        if streakDays >= 7 { progress += 0.01 }
        if streakDays >= 30 { progress += 0.01 }

        return min(1.0, max(0.0, progress))
    }

    // MARK: - Check Evolution

    public func canEvolve(pet: Pet) -> Bool {
        pet.progress >= 1.0 && pet.stage.nextStage != nil
    }

    public func evolve(pet: Pet) -> Pet {
        guard canEvolve(pet: pet), let nextStage = pet.stage.nextStage else {
            return pet
        }

        var evolvedPet = pet
        evolvedPet.stage = nextStage
        evolvedPet.progress = 0.0
        evolvedPet.weight *= 1.2
        evolvedPet.height *= 1.15
        evolvedPet.tailLength *= 1.1

        return evolvedPet
    }

    // MARK: - Status Description

    public func getStatusDescription(pet: Pet) -> String {
        switch pet.mood {
        case .happy:
            return "\(pet.name) is feeling happy and content!"
        case .excited:
            return "\(pet.name) is excited about your progress!"
        case .focused:
            return "\(pet.name) is focused and ready to help!"
        case .sleepy:
            return "\(pet.name) is getting sleepy... time to rest?"
        case .missing:
            return "\(pet.name) missed you! Welcome back!"
        }
    }

    public func getSceneDescription(scene: PetScene) -> String {
        switch scene {
        case .indoor:
            return "Relaxing at home"
        case .outdoor:
            return "Enjoying the outdoors"
        case .night:
            return "Under the starry sky"
        case .work:
            return "In work mode"
        }
    }
}

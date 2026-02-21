import Foundation

@MainActor
final class PetManager {
    func updatePetState(
        pet: Pet,
        tasks: [TaskItem],
        petStateService: PetStateService
    ) async -> Pet {
        var updatedPet = pet
        let completedToday = completedTasksForToday(tasks: tasks).count
        let totalToday = tasksForToday(tasks: tasks).count

        updatedPet.mood = await petStateService.calculateMood(
            lastInteraction: updatedPet.lastInteraction,
            tasksCompletedToday: completedToday,
            totalTasksToday: totalToday
        )

        updatedPet.scene = await petStateService.calculateScene(
            currentTime: Date(),
            hasTasks: totalToday > completedToday
        )

        return updatedPet
    }

    func updateStreak(_ streak: Streak, calendar: Calendar = .current) -> Streak {
        var updatedStreak = streak
        let today = calendar.startOfDay(for: Date())

        if let lastActive = updatedStreak.lastActiveDate {
            let lastActiveDay = calendar.startOfDay(for: lastActive)

            if calendar.isDate(lastActiveDay, inSameDayAs: today) {
                return updatedStreak
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      calendar.isDate(lastActiveDay, inSameDayAs: yesterday) {
                updatedStreak.currentStreak += 1
            } else {
                updatedStreak.currentStreak = 1
            }
        } else {
            updatedStreak.currentStreak = 1
        }

        updatedStreak.lastActiveDate = today
        updatedStreak.longestStreak = max(updatedStreak.longestStreak, updatedStreak.currentStreak)

        return updatedStreak
    }

    func canEvolve(
        pet: Pet,
        petStateService: PetStateService
    ) async -> PetStage? {
        let canEvolve = await petStateService.canEvolve(pet: pet)
        guard canEvolve else { return nil }
        return pet.stage.nextStage
    }

    func completeEvolution(from pet: Pet, to stage: PetStage) -> Pet {
        var updatedPet = pet
        updatedPet.stage = stage
        updatedPet.progress = 0.0
        updatedPet.weight *= EvolutionMultipliers.weight
        updatedPet.height *= EvolutionMultipliers.height
        updatedPet.tailLength *= EvolutionMultipliers.tailLength
        return updatedPet
    }

    private func tasksForToday(tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDateInToday(dueDate)
        }
    }

    private func completedTasksForToday(tasks: [TaskItem]) -> [TaskItem] {
        tasksForToday(tasks: tasks).filter(\.isCompleted)
    }
}

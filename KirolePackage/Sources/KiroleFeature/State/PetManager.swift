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

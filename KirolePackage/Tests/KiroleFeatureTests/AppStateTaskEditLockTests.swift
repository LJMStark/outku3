import Foundation
import Testing
@testable import KiroleFeature

@Suite("AppState Task Edit Lock")
struct AppStateTaskEditLockTests {
    @Test("Connected focus rejects editing the active task before local mutation")
    @MainActor
    func connectedFocusRejectsActiveTaskEdit() async {
        let state = AppState.makeForTesting()
        let task = TaskItem(id: "active-task", title: "Before", source: .apple)
        state.tasks = [task]
        state.taskLibraryStabilityTask?.cancel()
        state.taskLibraryStabilityTask = nil
        state.taskLibraryStabilityState = TaskLibraryStabilityState()

        await #expect(throws: TaskEditingError.activeOnConnectedDevice) {
            try await state.editTask(
                task,
                title: "After",
                priority: .high,
                dueDate: nil,
                notes: nil,
                editingContext: TaskEditingContext(
                    isDeviceConnected: true,
                    activeFocusTaskID: task.id
                )
            )
        }

        #expect(state.tasks.first?.title == "Before")
        #expect(state.taskLibraryStabilityState.deadline == nil)
        state.cancelPendingBLESync()
        state.taskLibraryStabilityTask?.cancel()
        state.taskLibraryPhasePreparationTasks.values.forEach { $0.cancel() }
    }

    @Test("Disconnected focus allows editing and keeps the three-minute stability window")
    @MainActor
    func disconnectedFocusAllowsEditWithStabilityWindow() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let previousTasks = try await LocalStorage.shared.loadTasks()
            let state = AppState.makeForTesting()
            let task = TaskItem(id: "active-task", title: "Before", source: .apple)
            state.tasks = [task]
            state.taskLibraryStabilityTask?.cancel()
            state.taskLibraryStabilityTask = nil
            state.taskLibraryStabilityState = TaskLibraryStabilityState()

            try await state.editTask(
                task,
                title: "After",
                priority: .high,
                dueDate: nil,
                notes: nil,
                editingContext: TaskEditingContext(
                    isDeviceConnected: false,
                    activeFocusTaskID: task.id
                )
            )

            #expect(state.tasks.first?.title == "After")
            #expect(state.taskLibraryStabilityState.deadline != nil)

            state.cancelPendingBLESync()
            state.taskLibraryStabilityTask?.cancel()
            state.taskLibraryPhasePreparationTasks.values.forEach { $0.cancel() }
            try await LocalStorage.shared.saveTasks(previousTasks ?? [])
        }
    }
}

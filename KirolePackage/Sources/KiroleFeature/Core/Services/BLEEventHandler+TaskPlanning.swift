import Foundation

extension BLEEventHandler {
    static func plannedTaskOperationReceipt(
        _ log: EventLog,
        tasks: [TaskItem] = AppState.shared.tasks
    ) -> TaskOperationReceipt? {
        guard let action = TaskListSnapshotAction(eventType: log.eventType),
              action == .completeTask || action == .skipTask,
              let operationID = log.operationID else {
            return nil
        }
        guard operationID != 0 else {
            return TaskOperationReceipt(action: action, operationID: 0, result: .invalidRequest)
        }

        guard let taskID = log.taskId, !taskID.isEmpty else {
            return TaskOperationReceipt(action: action, operationID: operationID, result: .invalidRequest)
        }
        guard let task = resolveTask(taskId: taskID, in: tasks) else {
            return TaskOperationReceipt(action: action, operationID: operationID, result: .taskNotFound)
        }
        if action == .completeTask, !task.allowsCompletionChanges {
            return TaskOperationReceipt(action: action, operationID: operationID, result: .invalidRequest)
        }
        let result: TaskListSnapshotResultCode = action == .completeTask && task.isCompleted
            ? .alreadyApplied
            : .applied
        return TaskOperationReceipt(action: action, operationID: operationID, result: result)
    }
}

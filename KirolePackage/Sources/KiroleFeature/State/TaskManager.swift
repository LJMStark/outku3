import Foundation

@MainActor
final class TaskManager {
    func tasksForToday(tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDateInToday(dueDate)
        }
    }

    func completedTasksForToday(tasks: [TaskItem]) -> [TaskItem] {
        tasksForToday(tasks: tasks).filter(\.isCompleted)
    }

    func statistics(tasks: [TaskItem], now: Date = Date()) -> TaskStatistics {
        let calendar = Calendar.current
        let todayTasks = tasksForToday(tasks: tasks)
        let todayCompleted = todayTasks.filter(\.isCompleted).count

        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let weekTasks = tasksDueBetween(tasks: tasks, start: weekStart, end: now)
        let weekCompleted = weekTasks.filter(\.isCompleted).count

        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let monthTasks = tasksDueBetween(tasks: tasks, start: thirtyDaysAgo, end: now)
        let monthCompleted = monthTasks.filter(\.isCompleted).count

        return TaskStatistics(
            todayCompleted: todayCompleted,
            todayTotal: todayTasks.count,
            pastWeekCompleted: weekCompleted,
            pastWeekTotal: weekTasks.count,
            last30DaysCompleted: monthCompleted,
            last30DaysTotal: monthTasks.count
        )
    }

    func tasksDueBetween(tasks: [TaskItem], start: Date, end: Date) -> [TaskItem] {
        tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= start && dueDate <= end
        }
    }

    func withTask(_ tasks: [TaskItem], updatedTask: TaskItem) -> [TaskItem] {
        tasks.map { $0.id == updatedTask.id ? updatedTask : $0 }
    }

    func addingTask(_ tasks: [TaskItem], task: TaskItem) -> [TaskItem] {
        tasks + [task]
    }

    func removingTask(_ tasks: [TaskItem], taskID: String) -> [TaskItem] {
        tasks.filter { $0.id != taskID }
    }

    func removingTasks(from source: EventSource, tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.source != source }
    }

    func mergedTasks(nonGoogleTasks: [TaskItem], syncedTasks: [TaskItem]) -> [TaskItem] {
        nonGoogleTasks + syncedTasks
    }
}

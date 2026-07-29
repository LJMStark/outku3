// Test data builders for the BLE protocol simulation suites.
//
// Split out of BLEProtocolSimulationSupport.swift to keep both files inside the repo's
// 800-line ceiling (AGENTS.md / coding-style). This file is the fixture *input* data;
// the simulated device and the wire parsers that read those bytes back live there.

import Foundation
@testable import KiroleFeature
struct ProtocolFixtures {
    let timestamp: UInt32 = 1_767_225_600
    let taskId = "task-ble-plan"
    let eventId = "event-hw-sync"

    var pet: Pet {
        Pet(name: "Tiko", mood: .happy)
    }

    var tasks: [TaskItem] {
        [
            TaskItem(
                id: taskId,
                title: "Plan BLE",
                isCompleted: false,
                dueDate: sampleDate(hour: 8, minute: 30),
                priority: .high
            ),
            TaskItem(
                id: "task-review-packet",
                title: "Review packet",
                isCompleted: true,
                dueDate: sampleDate(hour: 10, minute: 0),
                priority: .medium
            ),
            TaskItem(
                id: "task-future",
                title: "Tomorrow only",
                isCompleted: false,
                dueDate: tomorrowDate(),
                priority: .low
            ),
        ]
    }

    var events: [CalendarEvent] {
        [
            CalendarEvent(
                id: eventId,
                title: "HW Sync",
                startTime: sampleDate(hour: 9, minute: 30),
                endTime: sampleDate(hour: 10, minute: 0)
            ),
            CalendarEvent(
                id: "event-tomorrow",
                title: "Future Event",
                startTime: tomorrowDate(),
                endTime: tomorrowDate()
            ),
        ]
    }

    var weather: Weather {
        Weather(temperature: -3, highTemp: 4, lowTemp: -6, condition: .rainy, location: "Shenzhen")
    }

    var dayPack: DayPack {
        DayPack(
            date: fixedDate(),
            deviceMode: .interactive,
            focusChallengeEnabled: true,
            petDialogue: "Small steps count.",
            daySummary: "Two events today. Take a break before noon.",
            firstUp: "09:30 HW Sync",
            settlementReview: "You completed 1 of 2 planned items. You focused for 2h 5m today.",
            settlementQuote: "All clear! You finished everything you set out to do.",
            events: [
                EventSummary(
                    time: "09:30",
                    endTime: "10:00",
                    title: "HW Sync",
                    description: "Bring the logic analyzer.",
                    category: .meetings,
                    supportText: "Take a moment to gather your thoughts."
                ),
            ],
            topTasks: [
                TaskSummary(id: taskId, title: "Plan BLE", isCompleted: false, priority: 2),
                TaskSummary(id: "task-review-packet", title: "Review packet", isCompleted: true, priority: 1),
            ],
            settlementData: SettlementData(
                tasksCompleted: 1,
                tasksTotal: 2,
                pointsEarned: 42,
                petMood: "happy",
                summaryMessage: "Packets parsed cleanly.",
                encouragementMessage: "Keep the contract small.",
                totalFocusMinutes: 35,
                focusSessionCount: 1,
                longestFocusMinutes: 35,
                interruptionCount: 0,
                totalEnergyBottles: 1
            )
        )
    }

    var taskInPage: TaskInPageData {
        TaskInPageData(
            taskId: taskId,
            taskTitle: "Plan BLE",
            taskDescription: "Check every packet before hardware.",
            encouragement: "Stay with the next byte.",
            focusChallengeActive: true
        )
    }

    private func sampleDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func tomorrowDate() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private func fixedDate() -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 5, day: 7).date ?? Date()
    }
}

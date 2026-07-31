import Foundation
import Testing
@testable import KiroleFeature

@Suite("DayPack refresh arbitration")
struct DayPackRefreshArbiterTests {
    private let now = Date(timeIntervalSince1970: 1_785_975_900)

    @Test("an automatic sync during an active event ignores dialogue first-up and progress-only changes")
    func automaticActiveEventDefersPresentationOnlyChange() {
        let task = todayTask()
        let baseline = makeDayPack(
            petDialogue: "Lunch starts soon.",
            firstUp: "13:05 lunch",
            settlement: settlement(completed: 0)
        )
        let presentationUpdate = makeDayPack(
            petDialogue: "Enjoy lunch.",
            firstUp: "Draft release notes",
            settlement: settlement(completed: 1)
        )

        #expect(baseline.stableFingerprint() != presentationUpdate.stableFingerprint())
        #expect(
            baseline.refreshSemanticFingerprint(allTasks: [task], at: now)
                == presentationUpdate.refreshSemanticFingerprint(allTasks: [task], at: now)
        )
        for trigger: BLESyncTrigger in [.automatic, .requestRefresh, .deviceWake, .background] {
            #expect(
                !DayPackRefreshArbiter.shouldSend(
                    trigger: trigger,
                    wireContentChanged: true,
                    hasActiveTimedEvent: true,
                    hasPreviousSemanticFingerprint: true,
                    semanticContentChanged: false
                )
            )
        }
    }

    @Test("a manual sync during an active event still sends a presentation update")
    func manualActiveEventSendsPresentationUpdate() {
        #expect(
            DayPackRefreshArbiter.shouldSend(
                trigger: .manual,
                wireContentChanged: true,
                hasActiveTimedEvent: true,
                hasPreviousSemanticFingerprint: true,
                semanticContentChanged: false
            )
        )
    }

    @Test("a task change during an active event sends the updated DayPack")
    func taskChangeDuringActiveEventSends() {
        let openTask = todayTask(isCompleted: false)
        let completedTask = todayTask(isCompleted: true)
        let baseline = makeDayPack(topTask: TaskSummary(from: openTask))
        let taskUpdate = makeDayPack(topTask: TaskSummary(from: completedTask))

        #expect(
            baseline.refreshSemanticFingerprint(allTasks: [openTask], at: now)
                != taskUpdate.refreshSemanticFingerprint(allTasks: [completedTask], at: now)
        )
        #expect(
            DayPackRefreshArbiter.shouldSend(
                trigger: .automatic,
                wireContentChanged: baseline.stableFingerprint() != taskUpdate.stableFingerprint(),
                hasActiveTimedEvent: true,
                hasPreviousSemanticFingerprint: true,
                semanticContentChanged: true
            )
        )
    }

    @Test("support-text changes during an active event send the updated DayPack")
    func supportTextChangeDuringActiveEventSends() {
        let task = todayTask()
        let baseline = makeDayPack(eventSupportText: "Keep the next step small.")
        let supportUpdate = makeDayPack(eventSupportText: "Take one clear next step.")

        #expect(
            baseline.refreshSemanticFingerprint(allTasks: [task], at: now)
                != supportUpdate.refreshSemanticFingerprint(allTasks: [task], at: now)
        )
        #expect(
            DayPackRefreshArbiter.shouldSend(
                trigger: .requestRefresh,
                wireContentChanged: baseline.stableFingerprint() != supportUpdate.stableFingerprint(),
                hasActiveTimedEvent: true,
                hasPreviousSemanticFingerprint: true,
                semanticContentChanged: true
            )
        )
    }

    @Test("outside an active timed event a presentation update sends normally")
    func presentationUpdateOutsideActiveEventSends() {
        #expect(
            DayPackRefreshArbiter.shouldSend(
                trigger: .deviceWake,
                wireContentChanged: true,
                hasActiveTimedEvent: false,
                hasPreviousSemanticFingerprint: true,
                semanticContentChanged: false
            )
        )
    }

    @Test("without a semantic baseline the first active-event sync sends once")
    func firstActiveEventSyncEstablishesSemanticBaseline() {
        #expect(
            DayPackRefreshArbiter.shouldSend(
                trigger: .automatic,
                wireContentChanged: true,
                hasActiveTimedEvent: true,
                hasPreviousSemanticFingerprint: false,
                semanticContentChanged: false
            )
        )
    }

    @Test("only a currently running timed event activates the deferral window")
    func activeTimedEventDetection() {
        let lunch = CalendarEvent(
            id: "lunch",
            title: "lunch",
            startTime: now.addingTimeInterval(-60),
            endTime: now.addingTimeInterval(60)
        )
        let allDay = CalendarEvent(
            id: "all-day",
            title: "All day",
            startTime: now.addingTimeInterval(-60),
            endTime: now.addingTimeInterval(60),
            isAllDay: true
        )

        #expect(DayPackRefreshArbiter.hasActiveTimedEvent(in: [lunch], at: now))
        #expect(!DayPackRefreshArbiter.hasActiveTimedEvent(in: [allDay], at: now))
    }

    private func todayTask(isCompleted: Bool = false) -> TaskItem {
        TaskItem(
            id: "draft",
            title: "Draft release notes",
            isCompleted: isCompleted,
            dueDate: now,
            priority: .high,
            notes: "Ship the BLE fix."
        )
    }

    private func makeDayPack(
        petDialogue: String = "Lunch starts soon.",
        firstUp: String = "13:05 lunch",
        settlement: SettlementData? = nil,
        eventSupportText: String = "Keep the next step small.",
        topTask: TaskSummary = TaskSummary(
            id: "draft",
            title: "Draft release notes",
            isCompleted: false,
            priority: TaskPriority.high.rawValue,
            dueTime: "13:30"
        )
    ) -> DayPack {
        DayPack(
            date: now,
            petDialogue: petDialogue,
            firstUp: firstUp,
            events: [
                EventSummary(
                    time: "13:05",
                    endTime: "13:35",
                    title: "lunch",
                    description: "",
                    supportText: eventSupportText
                )
            ],
            topTasks: [topTask],
            settlementData: settlement ?? self.settlement(completed: 0)
        )
    }

    private func settlement(completed: Int) -> SettlementData {
        SettlementData(
            tasksCompleted: completed,
            tasksTotal: 2,
            pointsEarned: completed * 10,
            petMood: "happy",
            summaryMessage: "",
            encouragementMessage: ""
        )
    }
}

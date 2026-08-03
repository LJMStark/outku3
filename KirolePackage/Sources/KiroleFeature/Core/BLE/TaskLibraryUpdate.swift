import CryptoKit
import Foundation

public struct TaskLibraryCommittedSnapshot: Sendable, Equatable, Codable {
    public let state: TaskLibraryCommittedState
    public let records: [TaskLibraryRecord]
    public let phaseSourceFingerprints: [String: String]
    public let hasCompleteRecords: Bool
    public let personaFingerprint: String

    public init(
        state: TaskLibraryCommittedState,
        records: [TaskLibraryRecord],
        phaseSourceFingerprints: [String: String],
        hasCompleteRecords: Bool = true,
        personaFingerprint: String = ""
    ) {
        self.state = state
        self.records = records
        self.phaseSourceFingerprints = phaseSourceFingerprints
        self.hasCompleteRecords = hasCompleteRecords
        self.personaFingerprint = personaFingerprint
    }
}

public enum TaskLibraryPendingValidation: Sendable, Equatable, Codable {
    case completeSource(String)
    case taskRemovals([String])
    case hardwareProjection(String)

    @MainActor
    func matchesCurrentSource() -> Bool {
        let appState = AppState.shared
        switch self {
        case .completeSource(let fingerprint):
            return TaskLibrarySourceFingerprint.make(
                tasks: appState.tasks,
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions
            ) == fingerprint
        case .taskRemovals(let taskIDs):
            let eligibleIDs = Set(appState.tasks.lazy
                .filter { !$0.isCompleted && !$0.pendingDeletion }
                .map(\.hardwareIdentifier))
            return taskIDs.allSatisfy { !eligibleIDs.contains($0) }
        case .hardwareProjection(let fingerprint):
            return TaskLibrarySourceFingerprint.make(
                tasks: appState.tasksForHardwarePresentation(),
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions
            ) == fingerprint
        }
    }
}

enum TaskLibraryPhaseSourceFingerprint {
    static func persona(
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> String {
        if let customID = userProfile.customCompanionId {
            let revision = customCompanions
                .first(where: { $0.id == customID })?
                .updatedAt.timeIntervalSinceReferenceDate.bitPattern ?? 0
            return "custom|\(customID.uuidString)|\(revision)"
        }
        return "built-in|\(userProfile.companionCharacter.rawValue)|\(userProfile.intimacyStage.rawValue)"
    }

    static func make(
        task: TaskItem,
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> String {
        var parts = [task.title, task.notes ?? ""]
        parts.append(persona(
            userProfile: userProfile,
            customCompanions: customCompanions
        ))
        return digest(parts)
    }

    private static func digest(_ parts: [String]) -> String {
        var framed = Data()
        for part in parts {
            let bytes = Data(part.utf8)
            var length = UInt64(bytes.count).bigEndian
            Swift.withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
            framed.append(bytes)
        }
        return SHA256.hash(data: framed)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum TaskLibraryUpdateScope: Sendable, Equatable, Codable {
    case complete
    case taskRemovals(Set<String>)
    case hardwareQueue
}

struct TaskLibraryPreparedUpdate: Sendable, Equatable {
    let transaction: TaskLibraryTransaction
    let targetRecords: [TaskLibraryRecord]
    let phaseSourceFingerprints: [String: String]
    let validation: TaskLibraryPendingValidation
    let personaFingerprint: String
}

enum TaskLibraryUpdatePlanner {
    static func tasksNeedingPhaseText(
        tasks: [TaskItem],
        baseline: TaskLibraryCommittedSnapshot?,
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> [TaskItem] {
        let existingIDs = Set(baseline?.records.map(\.taskID) ?? [])
        let oldFingerprints = baseline?.phaseSourceFingerprints ?? [:]
        return tasks.filter { task in
            guard !task.isCompleted, !task.pendingDeletion else { return false }
            let taskID = task.hardwareIdentifier
            let fingerprint = TaskLibraryPhaseSourceFingerprint.make(
                task: task,
                userProfile: userProfile,
                customCompanions: customCompanions
            )
            return !existingIDs.contains(taskID) || oldFingerprints[taskID] != fingerprint
        }
    }

    static func makeUpdate(
        tasks: [TaskItem],
        baseline: TaskLibraryCommittedSnapshot?,
        version: TaskLibraryVersion,
        scope: TaskLibraryUpdateScope,
        preparedPhaseTexts: [String: TaskLibraryPhaseTexts],
        userProfile: UserProfile,
        customCompanions: [CustomCompanion],
        forceFullTransaction: Bool = false
    ) throws -> TaskLibraryPreparedUpdate {
        if forceFullTransaction {
            return try makeCompleteUpdate(
                tasks: tasks,
                baseline: baseline,
                version: version,
                preparedPhaseTexts: preparedPhaseTexts,
                userProfile: userProfile,
                customCompanions: customCompanions,
                forceFullTransaction: true
            )
        }
        switch scope {
        case .complete:
            return try makeCompleteUpdate(
                tasks: tasks,
                baseline: baseline,
                version: version,
                preparedPhaseTexts: preparedPhaseTexts,
                userProfile: userProfile,
                customCompanions: customCompanions,
                forceFullTransaction: false
            )
        case .hardwareQueue:
            let update = try makeCompleteUpdate(
                tasks: tasks,
                baseline: baseline,
                version: version,
                preparedPhaseTexts: preparedPhaseTexts,
                userProfile: userProfile,
                customCompanions: customCompanions,
                forceFullTransaction: false
            )
            return TaskLibraryPreparedUpdate(
                transaction: update.transaction,
                targetRecords: update.targetRecords,
                phaseSourceFingerprints: update.phaseSourceFingerprints,
                validation: .hardwareProjection(TaskLibrarySourceFingerprint.make(
                    tasks: tasks,
                    userProfile: userProfile,
                    customCompanions: customCompanions
                )),
                personaFingerprint: update.personaFingerprint
            )
        case .taskRemovals(let taskIDs):
            guard let baseline else {
                return try makeCompleteUpdate(
                    tasks: tasks,
                    baseline: nil,
                    version: version,
                    preparedPhaseTexts: preparedPhaseTexts,
                    userProfile: userProfile,
                    customCompanions: customCompanions,
                    forceFullTransaction: false
                )
            }
            let remaining = baseline.records
                .filter { !taskIDs.contains($0.taskID) }
                .enumerated()
                .map { index, record in
                    TaskLibraryRecord(
                        taskID: record.taskID,
                        order: UInt32(index),
                        title: record.title,
                        detail: record.detail,
                        dueTimestamp: record.dueTimestamp,
                        priority: record.priority,
                        phaseTexts: record.phaseTexts
                    )
                }
            var remainingByID: [String: TaskLibraryRecord] = [:]
            for record in remaining where remainingByID[record.taskID] == nil {
                remainingByID[record.taskID] = record
            }
            let upserts = remaining.filter { record in
                baseline.records.first(where: { $0.taskID == record.taskID }) != record
            }
            let deletions = baseline.records.map(\.taskID).filter { remainingByID[$0] == nil }
            let transaction = TaskLibraryTransaction.incremental(
                from: baseline.state,
                to: version,
                upserts: upserts,
                deletions: deletions
            )
            let fingerprints = baseline.phaseSourceFingerprints.filter {
                remainingByID[$0.key] != nil
            }
            return TaskLibraryPreparedUpdate(
                transaction: transaction,
                targetRecords: remaining,
                phaseSourceFingerprints: fingerprints,
                validation: .taskRemovals(Array(taskIDs).sorted()),
                personaFingerprint: baseline.personaFingerprint
            )
        }
    }

    private static func makeCompleteUpdate(
        tasks: [TaskItem],
        baseline: TaskLibraryCommittedSnapshot?,
        version: TaskLibraryVersion,
        preparedPhaseTexts: [String: TaskLibraryPhaseTexts],
        userProfile: UserProfile,
        customCompanions: [CustomCompanion],
        forceFullTransaction: Bool
    ) throws -> TaskLibraryPreparedUpdate {
        var oldRecords: [String: TaskLibraryRecord] = [:]
        for record in baseline?.records ?? [] where oldRecords[record.taskID] == nil {
            oldRecords[record.taskID] = record
        }
        let oldFingerprints = baseline?.phaseSourceFingerprints ?? [:]
        let fallback = userProfile.customCompanionId == nil
            ? TaskLibraryPhaseTexts.localFallback(for: userProfile.companionCharacter)
            : .localFallback
        let eligible = tasks.filter { !$0.isCompleted && !$0.pendingDeletion }
        var targetRecords: [TaskLibraryRecord] = []
        var targetFingerprints: [String: String] = [:]
        targetRecords.reserveCapacity(eligible.count)

        for (index, task) in eligible.enumerated() {
            guard let order = UInt32(exactly: index) else {
                throw TaskLibraryCodecError.recordCountOverflow
            }
            let taskID = task.hardwareIdentifier
            let fingerprint = TaskLibraryPhaseSourceFingerprint.make(
                task: task,
                userProfile: userProfile,
                customCompanions: customCompanions
            )
            let phaseTexts: TaskLibraryPhaseTexts
            if oldFingerprints[taskID] == fingerprint,
               let oldRecord = oldRecords[taskID] {
                phaseTexts = oldRecord.phaseTexts
            } else {
                phaseTexts = preparedPhaseTexts[taskID] ?? fallback
            }
            targetFingerprints[taskID] = fingerprint
            targetRecords.append(TaskLibraryRecord(
                task: task,
                order: order,
                phaseTexts: phaseTexts
            ))
        }

        let transaction: TaskLibraryTransaction
        if let baseline, !forceFullTransaction {
            var targetByID: [String: TaskLibraryRecord] = [:]
            for record in targetRecords where targetByID[record.taskID] == nil {
                targetByID[record.taskID] = record
            }
            let upserts = targetRecords.filter { oldRecords[$0.taskID] != $0 }
            let deletions = baseline.records.map(\.taskID).filter { targetByID[$0] == nil }
            transaction = .incremental(
                from: baseline.state,
                to: version,
                upserts: upserts,
                deletions: deletions
            )
        } else {
            transaction = TaskLibraryTransaction(version: version, records: targetRecords)
        }

        return TaskLibraryPreparedUpdate(
            transaction: transaction,
            targetRecords: targetRecords,
            phaseSourceFingerprints: targetFingerprints,
            validation: .completeSource(TaskLibrarySourceFingerprint.make(
                tasks: tasks,
                userProfile: userProfile,
                customCompanions: customCompanions
            )),
            personaFingerprint: TaskLibraryPhaseSourceFingerprint.persona(
                userProfile: userProfile,
                customCompanions: customCompanions
            )
        )
    }
}

struct TaskLibraryStabilityCheckpoint: Sendable, Codable {
    let state: TaskLibraryStabilityState
    let hardwareTasksBaseline: [TaskItem]?
    let hardwarePetDialogueBaseline: String
    let sourceFingerprint: String
}

struct TaskLibraryStabilityState: Sendable, Equatable, Codable {
    static let window: TimeInterval = 180

    private(set) var stableTaskIDs: Set<String> = []
    private(set) var urgentRemovalTaskIDs: Set<String> = []
    private(set) var hasUrgentHardwareQueueUpdate = false
    private(set) var deadline: Date?
    private(set) var generation: UInt64 = 0

    mutating func recordTaskChanges(
        from oldTasks: [TaskItem],
        to newTasks: [TaskItem],
        at now: Date,
        immediateRemovalTaskIDs: Set<String> = [],
        immediateQueueReorderTaskIDs: Set<String> = []
    ) -> Bool {
        let oldEligible = oldTasks.filter { !$0.isCompleted && !$0.pendingDeletion }
        let newEligible = newTasks.filter { !$0.isCompleted && !$0.pendingDeletion }
        var oldByID: [String: TaskItem] = [:]
        var newByID: [String: TaskItem] = [:]
        var oldOrder: [String: Int] = [:]
        var newOrder: [String: Int] = [:]
        let oldOrderEligible = oldEligible.filter {
            !immediateRemovalTaskIDs.contains($0.hardwareIdentifier)
        }
        for task in oldEligible where oldByID[task.hardwareIdentifier] == nil {
            oldByID[task.hardwareIdentifier] = task
        }
        for (index, task) in oldOrderEligible.enumerated() where oldOrder[task.hardwareIdentifier] == nil {
            oldOrder[task.hardwareIdentifier] = index
        }
        for (index, task) in newEligible.enumerated() where newByID[task.hardwareIdentifier] == nil {
            newByID[task.hardwareIdentifier] = task
            newOrder[task.hardwareIdentifier] = index
        }
        let allIDs = Set(oldByID.keys).union(newByID.keys)
        let changed = allIDs.filter { taskID in
            if immediateRemovalTaskIDs.contains(taskID),
               oldByID[taskID] != nil,
               newByID[taskID] == nil {
                return false
            }
            guard let old = oldByID[taskID], let new = newByID[taskID] else { return true }
            return old.title != new.title
                || old.notes != new.notes
                || old.dueDate != new.dueDate
                || old.todayDisplayDate != new.todayDisplayDate
                || old.priority != new.priority
                || (immediateQueueReorderTaskIDs.isEmpty
                    && oldOrder[taskID] != newOrder[taskID])
        }
        guard !changed.isEmpty else { return false }
        generation = generation == .max ? .max : generation + 1
        stableTaskIDs.formUnion(changed)
        urgentRemovalTaskIDs.subtract(changed)
        deadline = now.addingTimeInterval(Self.window)
        return true
    }

    mutating func promoteImmediateRemoval(taskID: String) {
        generation = generation == .max ? .max : generation + 1
        stableTaskIDs.remove(taskID)
        urgentRemovalTaskIDs.insert(taskID)
        if stableTaskIDs.isEmpty {
            deadline = nil
        }
    }

    mutating func promoteImmediateHardwareQueueUpdate() {
        generation = generation == .max ? .max : generation + 1
        hasUrgentHardwareQueueUpdate = true
    }

    func readyScope(at now: Date) -> TaskLibraryUpdateScope? {
        if !urgentRemovalTaskIDs.isEmpty {
            return .taskRemovals(urgentRemovalTaskIDs)
        }
        if hasUrgentHardwareQueueUpdate {
            return .hardwareQueue
        }
        if !stableTaskIDs.isEmpty, let deadline, deadline <= now {
            return .complete
        }
        return nil
    }

    mutating func markCommitted(
        scope: TaskLibraryUpdateScope,
        capturedGeneration: UInt64
    ) {
        switch scope {
        case .taskRemovals(let taskIDs):
            urgentRemovalTaskIDs.subtract(taskIDs)
        case .hardwareQueue:
            hasUrgentHardwareQueueUpdate = false
        case .complete:
            guard generation == capturedGeneration else { return }
            stableTaskIDs.removeAll()
            urgentRemovalTaskIDs.removeAll()
            deadline = nil
        }
    }
}

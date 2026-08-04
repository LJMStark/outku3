import Foundation

/// Version identity for the device task library. Both values are non-zero on the wire.
public struct TaskLibraryVersion: Sendable, Equatable, Codable {
    public let epoch: UInt32
    public let revision: UInt32

    public init(epoch: UInt32, revision: UInt32) {
        self.epoch = epoch
        self.revision = revision
    }
}

/// Exact device-side library identity reported on wake and persisted after a matching commit ACK.
public struct TaskLibraryCommittedState: Sendable, Equatable, Codable {
    public let version: TaskLibraryVersion
    public let contentCRC32: UInt32

    public init(version: TaskLibraryVersion, contentCRC32: UInt32) {
        self.version = version
        self.contentCRC32 = contentCRC32
    }
}

public enum TaskLibraryDeviceInventory: Sendable, Equatable, Codable {
    case missing
    case committed(TaskLibraryCommittedState)
}

public enum TaskLibraryFullSyncPolicy {
    public static func shouldSendFullLibrary(
        locallyCommitted: TaskLibraryCommittedState?,
        deviceInventory: TaskLibraryDeviceInventory?,
        hasPendingTransaction: Bool
    ) -> Bool {
        if hasPendingTransaction { return true }
        switch deviceInventory {
        case .missing:
            return true
        case .committed:
            return locallyCommitted == nil
        case nil:
            return locallyCommitted == nil
        }
    }
}

/// The three lines stored with one task. Firmware selects them by local focus time.
public struct TaskLibraryPhaseTexts: Sendable, Equatable, Codable {
    public let starting: String
    public let building: String
    public let deep: String

    public init(starting: String, building: String, deep: String) {
        self.starting = starting
        self.building = building
        self.deep = deep
    }

    /// Neutral fallback for a custom companion whose user-defined voice cannot be reproduced
    /// safely without AI.
    public static let localFallback = TaskLibraryPhaseTexts(
        starting: "Start with the smallest clear step.",
        building: "Keep moving through the useful middle.",
        deep: "Stay with the work that matters most."
    )

    public static func localFallback(
        for character: CompanionCharacter
    ) -> TaskLibraryPhaseTexts {
        switch character {
        case .joy:
            return TaskLibraryPhaseTexts(
                starting: "A tiny start still counts.",
                building: "Look at this task taking shape.",
                deep: "You found the good part; stay awhile."
            )
        case .silas:
            return TaskLibraryPhaseTexts(
                starting: "Begin gently; you are not alone.",
                building: "Keep going with quiet courage.",
                deep: "Stay steady; this work is being held."
            )
        case .nova:
            return TaskLibraryPhaseTexts(
                starting: "Take the first critical step.",
                building: "Keep the signal; drop the noise.",
                deep: "Protect this stretch of focused work."
            )
        }
    }

    /// Firmware uses its local focus clock. Minute 0 belongs to the first phase; negative input is
    /// treated defensively as 0 so a clock correction cannot select a later line.
    public func text(atElapsedMinutes elapsedMinutes: Int) -> String {
        switch max(0, elapsedMinutes) {
        case ...5:
            return starting
        case 6...15:
            return building
        default:
            return deep
        }
    }
}

/// One complete device task-library record.
public struct TaskLibraryRecord: Sendable, Equatable, Codable {
    public let taskID: String
    public let order: UInt32
    public let title: String
    public let detail: String
    public let dueTimestamp: UInt64?
    public let priority: TaskPriority
    public let phaseTexts: TaskLibraryPhaseTexts

    public init(
        taskID: String,
        order: UInt32,
        title: String,
        detail: String,
        dueTimestamp: UInt64? = nil,
        priority: TaskPriority = .medium,
        phaseTexts: TaskLibraryPhaseTexts
    ) {
        self.taskID = taskID
        self.order = order
        self.title = title
        self.detail = detail
        self.dueTimestamp = dueTimestamp
        self.priority = priority
        self.phaseTexts = phaseTexts
    }

    public init(task: TaskItem, order: UInt32, phaseTexts: TaskLibraryPhaseTexts) {
        self.init(
            taskID: task.hardwareIdentifier,
            order: order,
            title: task.title,
            detail: task.notes ?? "",
            dueTimestamp: task.dueDate.map {
                UInt64(max(0, $0.timeIntervalSince1970.rounded(.towardZero)))
            },
            priority: task.priority,
            phaseTexts: phaseTexts
        )
    }
}

public enum TaskLibraryTransactionKind: UInt8, Sendable, Equatable, Codable {
    case full = 0x00
    case incremental = 0x01
}

/// One atomic full replacement or incremental update. Incremental transactions are bound to the
/// exact previously committed version and CRC; firmware applies all upserts/deletions to a copy
/// and swaps it into view only after the complete transaction validates.
public struct TaskLibraryTransaction: Sendable, Equatable, Codable {
    public let kind: TaskLibraryTransactionKind
    public let baseState: TaskLibraryCommittedState?
    public let version: TaskLibraryVersion
    /// Full mode: every record. Incremental mode: only inserted or changed records.
    public let records: [TaskLibraryRecord]
    public let deletedTaskIDs: [String]

    public init(
        kind: TaskLibraryTransactionKind = .full,
        baseState: TaskLibraryCommittedState? = nil,
        version: TaskLibraryVersion,
        records: [TaskLibraryRecord],
        deletedTaskIDs: [String] = []
    ) {
        self.kind = kind
        self.baseState = baseState
        self.version = version
        self.records = records
        self.deletedTaskIDs = deletedTaskIDs
    }

    /// Builds the complete device library for the given local day. App array order is the device
    /// queue order. Only today's tasks are included (dueDate strictly today, or manually selected
    /// for today) — future, overdue and unselected undated tasks stay off the wire (2026-08-04
    /// product decision). At most `TaskLibraryMembership.maxRecords` tasks ship; the rest are
    /// dropped silently. That cap is a product policy, not a screen-display cap — the device
    /// still must never truncate a transaction itself.
    public static func fullLibrary(
        from tasks: [TaskItem],
        version: TaskLibraryVersion,
        now: Date,
        calendar: Calendar,
        phaseTexts: (TaskItem) -> TaskLibraryPhaseTexts = { _ in .localFallback }
    ) throws -> TaskLibraryTransaction {
        let incompleteTasks = TaskLibraryMembership.members(
            of: tasks,
            on: now,
            calendar: calendar
        )
        var records: [TaskLibraryRecord] = []
        records.reserveCapacity(incompleteTasks.count)
        for (index, task) in incompleteTasks.enumerated() {
            guard let order = UInt32(exactly: index) else {
                throw TaskLibraryCodecError.recordCountOverflow
            }
            records.append(TaskLibraryRecord(
                task: task,
                order: order,
                phaseTexts: phaseTexts(task)
            ))
        }
        return TaskLibraryTransaction(
            kind: .full,
            baseState: nil,
            version: version,
            records: records,
            deletedTaskIDs: []
        )
    }

    public static func incremental(
        from base: TaskLibraryCommittedState,
        to version: TaskLibraryVersion,
        upserts: [TaskLibraryRecord],
        deletions: [String]
    ) -> TaskLibraryTransaction {
        TaskLibraryTransaction(
            kind: .incremental,
            baseState: base,
            version: version,
            records: upserts,
            deletedTaskIDs: deletions
        )
    }
}

public enum TaskLibraryCommitResult: UInt8, Sendable, Equatable, Codable {
    case committed = 0x00
    case invalidPayload = 0x01
    case checksumMismatch = 0x02
    case capacityExceeded = 0x03
    case unsupportedVersion = 0x04
    case baseMismatch = 0x05
    case internalError = 0xFF
}

/// Device→App confirmation for the exact version and content CRC that became visible.
public struct TaskLibraryCommitAcknowledgement: Sendable, Equatable, Codable {
    public let version: TaskLibraryVersion
    public let result: TaskLibraryCommitResult
    public let contentCRC32: UInt32

    public init(
        version: TaskLibraryVersion,
        result: TaskLibraryCommitResult,
        contentCRC32: UInt32
    ) {
        self.version = version
        self.result = result
        self.contentCRC32 = contentCRC32
    }
}

public enum TaskLibraryCodecError: Error, Equatable, Sendable {
    case invalidVersion
    case invalidTransactionShape
    case unsupportedSubVersion(UInt8)
    case unsupportedTransactionKind(UInt8)
    case invalidTaskID
    case invalidPriority(UInt8)
    case recordCountOverflow
    case truncated(field: String)
    case fieldTooLong(field: String, length: Int, max: Int)
    case invalidUTF8(field: String)
    case invalidCommitResult(UInt8)
    case checksumMismatch(expected: UInt32, actual: UInt32)
    case trailingBytes(Int)
}

/// `0x23` task-library snapshot and acknowledgement codec.
public enum TaskLibraryCodec {
    public static let subVersion: UInt8 = 0x02
    public static let maxTaskIDBytes = 36
    public static let maxTitleBytes = 40
    public static let maxDetailBytes = DayPackTextBudget.taskDetail
    public static let maxPhaseTextBytes = DayPackTextBudget.taskPhaseText
    private static let taskTitleFallback = "Task"

    /// App→Device:
    /// `SubVersion | Kind | BaseEpoch | BaseRevision | BaseCRC | Epoch | Revision |
    /// UpsertCount(4) | Upserts[] | DeleteCount(4) | DeleteIDs[] | ContentCRC32`.
    public static func encodeTransaction(_ transaction: TaskLibraryTransaction) throws -> Data {
        try validate(version: transaction.version)
        switch transaction.kind {
        case .full:
            guard transaction.baseState == nil, transaction.deletedTaskIDs.isEmpty else {
                throw TaskLibraryCodecError.invalidTransactionShape
            }
        case .incremental:
            guard let baseState = transaction.baseState else {
                throw TaskLibraryCodecError.invalidTransactionShape
            }
            try validate(version: baseState.version)
        }
        guard transaction.records.count <= Int(UInt32.max) else {
            throw TaskLibraryCodecError.recordCountOverflow
        }
        guard transaction.deletedTaskIDs.count <= Int(UInt32.max) else {
            throw TaskLibraryCodecError.recordCountOverflow
        }

        var payload = Data()
        payload.append(subVersion)
        payload.append(transaction.kind.rawValue)
        payload.appendBigEndian(transaction.baseState?.version.epoch ?? 0)
        payload.appendBigEndian(transaction.baseState?.version.revision ?? 0)
        payload.appendBigEndian(transaction.baseState?.contentCRC32 ?? 0)
        payload.appendBigEndian(transaction.version.epoch)
        payload.appendBigEndian(transaction.version.revision)
        payload.appendBigEndian(UInt32(transaction.records.count))

        var seenTaskIDs: Set<String> = []
        for record in transaction.records {
            let taskID = record.taskID.asciiSanitizedForEInk()
            let taskIDLength = taskID.utf8.count
            guard !taskID.isEmpty,
                  taskIDLength <= maxTaskIDBytes,
                  seenTaskIDs.insert(taskID).inserted else {
                throw TaskLibraryCodecError.invalidTaskID
            }
            payload.appendString(taskID, maxLength: maxTaskIDBytes)
            payload.appendBigEndian(record.order)
            payload.appendString(
                record.title,
                maxLength: maxTitleBytes,
                fallbackIfSanitizedEmpty: taskTitleFallback
            )
            payload.appendString(record.detail, maxLength: maxDetailBytes)
            if let dueTimestamp = record.dueTimestamp {
                payload.append(0x01)
                payload.appendBigEndian(dueTimestamp)
            } else {
                payload.append(0x00)
                payload.appendBigEndian(UInt64(0))
            }
            payload.append(UInt8(record.priority.rawValue))
            payload.appendString(record.phaseTexts.starting, maxLength: maxPhaseTextBytes)
            payload.appendString(record.phaseTexts.building, maxLength: maxPhaseTextBytes)
            payload.appendString(record.phaseTexts.deep, maxLength: maxPhaseTextBytes)
        }

        payload.appendBigEndian(UInt32(transaction.deletedTaskIDs.count))
        for taskIDValue in transaction.deletedTaskIDs {
            let taskID = taskIDValue.asciiSanitizedForEInk()
            guard !taskID.isEmpty,
                  taskID.utf8.count <= maxTaskIDBytes,
                  seenTaskIDs.insert(taskID).inserted else {
                throw TaskLibraryCodecError.invalidTaskID
            }
            payload.appendString(taskID, maxLength: maxTaskIDBytes)
        }

        payload.appendBigEndian(CRC32.ieee(payload))
        return payload
    }

    public static func committedState(
        for transaction: TaskLibraryTransaction
    ) throws -> TaskLibraryCommittedState {
        let payload = try encodeTransaction(transaction)
        return TaskLibraryCommittedState(
            version: transaction.version,
            contentCRC32: payload.bigEndianUInt32(at: payload.count - 4)
        )
    }

    public static func decodeTransaction(_ payload: Data) throws -> TaskLibraryTransaction {
        guard payload.count >= 34 else {
            throw TaskLibraryCodecError.truncated(field: "transaction")
        }
        let crcOffset = payload.count - 4
        let body = payload.subdata(in: 0..<crcOffset)
        let expectedCRC = payload.bigEndianUInt32(at: crcOffset)
        let actualCRC = CRC32.ieee(body)
        guard expectedCRC == actualCRC else {
            throw TaskLibraryCodecError.checksumMismatch(expected: expectedCRC, actual: actualCRC)
        }

        var reader = Reader(data: body)
        let receivedSubVersion = try reader.readByte(field: "subVersion")
        guard receivedSubVersion == subVersion else {
            throw TaskLibraryCodecError.unsupportedSubVersion(receivedSubVersion)
        }
        let kindByte = try reader.readByte(field: "kind")
        guard let kind = TaskLibraryTransactionKind(rawValue: kindByte) else {
            throw TaskLibraryCodecError.unsupportedTransactionKind(kindByte)
        }
        let baseEpoch = try reader.readUInt32(field: "baseEpoch")
        let baseRevision = try reader.readUInt32(field: "baseRevision")
        let baseCRC32 = try reader.readUInt32(field: "baseCRC32")
        let baseState: TaskLibraryCommittedState?
        if baseEpoch == 0, baseRevision == 0, baseCRC32 == 0 {
            baseState = nil
        } else {
            let baseVersion = TaskLibraryVersion(epoch: baseEpoch, revision: baseRevision)
            try validate(version: baseVersion)
            baseState = TaskLibraryCommittedState(
                version: baseVersion,
                contentCRC32: baseCRC32
            )
        }
        let version = TaskLibraryVersion(
            epoch: try reader.readUInt32(field: "epoch"),
            revision: try reader.readUInt32(field: "revision")
        )
        try validate(version: version)
        let recordCount = try reader.readUInt32(field: "recordCount")

        var records: [TaskLibraryRecord] = []
        var seenTaskIDs: Set<String> = []
        for index in 0..<recordCount {
            let prefix = "records[\(index)]"
            let taskID = try reader.readString(field: "\(prefix).taskID", max: maxTaskIDBytes)
            guard !taskID.isEmpty, seenTaskIDs.insert(taskID).inserted else {
                throw TaskLibraryCodecError.invalidTaskID
            }
            let order = try reader.readUInt32(field: "\(prefix).order")
            let title = try reader.readString(field: "\(prefix).title", max: maxTitleBytes)
            let detail = try reader.readString(field: "\(prefix).detail", max: maxDetailBytes)
            let hasDueDate = try reader.readByte(field: "\(prefix).hasDueDate")
            guard hasDueDate <= 1 else {
                throw TaskLibraryCodecError.invalidTransactionShape
            }
            let dueTimestampValue = try reader.readUInt64(field: "\(prefix).dueTimestamp")
            guard hasDueDate == 1 || dueTimestampValue == 0 else {
                throw TaskLibraryCodecError.invalidTransactionShape
            }
            let priorityByte = try reader.readByte(field: "\(prefix).priority")
            guard let priority = TaskPriority(rawValue: Int(priorityByte)) else {
                throw TaskLibraryCodecError.invalidPriority(priorityByte)
            }
            let starting = try reader.readString(field: "\(prefix).starting", max: maxPhaseTextBytes)
            let building = try reader.readString(field: "\(prefix).building", max: maxPhaseTextBytes)
            let deep = try reader.readString(field: "\(prefix).deep", max: maxPhaseTextBytes)
            records.append(TaskLibraryRecord(
                taskID: taskID,
                order: order,
                title: title,
                detail: detail,
                dueTimestamp: hasDueDate == 1 ? dueTimestampValue : nil,
                priority: priority,
                phaseTexts: TaskLibraryPhaseTexts(
                    starting: starting,
                    building: building,
                    deep: deep
                )
            ))
        }
        let deletionCount = try reader.readUInt32(field: "deletionCount")
        var deletedTaskIDs: [String] = []
        for index in 0..<deletionCount {
            let taskID = try reader.readString(
                field: "deletions[\(index)]",
                max: maxTaskIDBytes
            )
            guard !taskID.isEmpty, seenTaskIDs.insert(taskID).inserted else {
                throw TaskLibraryCodecError.invalidTaskID
            }
            deletedTaskIDs.append(taskID)
        }
        try reader.requireEnd()
        let transaction = TaskLibraryTransaction(
            kind: kind,
            baseState: baseState,
            version: version,
            records: records,
            deletedTaskIDs: deletedTaskIDs
        )
        switch kind {
        case .full:
            guard baseState == nil, deletedTaskIDs.isEmpty else {
                throw TaskLibraryCodecError.invalidTransactionShape
            }
        case .incremental:
            guard baseState != nil else {
                throw TaskLibraryCodecError.invalidTransactionShape
            }
        }
        return transaction
    }

    /// Device→App: `SubVersion | Epoch | Revision | Result | ContentCRC32`.
    public static func encodeAcknowledgement(
        _ acknowledgement: TaskLibraryCommitAcknowledgement
    ) -> Data {
        var payload = Data()
        payload.append(subVersion)
        payload.appendBigEndian(acknowledgement.version.epoch)
        payload.appendBigEndian(acknowledgement.version.revision)
        payload.append(acknowledgement.result.rawValue)
        payload.appendBigEndian(acknowledgement.contentCRC32)
        return payload
    }

    public static func decodeAcknowledgement(
        _ payload: Data
    ) throws -> TaskLibraryCommitAcknowledgement {
        var reader = Reader(data: payload)
        let receivedSubVersion = try reader.readByte(field: "subVersion")
        guard receivedSubVersion == subVersion else {
            throw TaskLibraryCodecError.unsupportedSubVersion(receivedSubVersion)
        }
        let version = TaskLibraryVersion(
            epoch: try reader.readUInt32(field: "epoch"),
            revision: try reader.readUInt32(field: "revision")
        )
        try validate(version: version)
        let resultByte = try reader.readByte(field: "result")
        guard let result = TaskLibraryCommitResult(rawValue: resultByte) else {
            throw TaskLibraryCodecError.invalidCommitResult(resultByte)
        }
        let contentCRC32 = try reader.readUInt32(field: "contentCRC32")
        try reader.requireEnd()
        return TaskLibraryCommitAcknowledgement(
            version: version,
            result: result,
            contentCRC32: contentCRC32
        )
    }

    private static func validate(version: TaskLibraryVersion) throws {
        guard version.epoch != 0, version.revision != 0 else {
            throw TaskLibraryCodecError.invalidVersion
        }
    }
}

private extension TaskLibraryCodec {
    struct Reader {
        let data: Data
        var offset = 0

        mutating func readByte(field: String) throws -> UInt8 {
            try require(1, field: field)
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readUInt32(field: String) throws -> UInt32 {
            try require(4, field: field)
            defer { offset += 4 }
            return data.bigEndianUInt32(at: offset)
        }

        mutating func readUInt64(field: String) throws -> UInt64 {
            try require(8, field: field)
            defer { offset += 8 }
            return data.bigEndianUInt64(at: offset)
        }

        mutating func readString(field: String, max: Int) throws -> String {
            let length = Int(try readByte(field: field))
            guard length <= max else {
                throw TaskLibraryCodecError.fieldTooLong(field: field, length: length, max: max)
            }
            try require(length, field: field)
            let bytes = data.subdata(in: offset..<(offset + length))
            offset += length
            guard let value = String(data: bytes, encoding: .utf8) else {
                throw TaskLibraryCodecError.invalidUTF8(field: field)
            }
            return value
        }

        func require(_ count: Int, field: String) throws {
            guard count >= 0, offset <= data.count - count else {
                throw TaskLibraryCodecError.truncated(field: field)
            }
        }

        func requireEnd() throws {
            guard offset == data.count else {
                throw TaskLibraryCodecError.trailingBytes(data.count - offset)
            }
        }
    }
}

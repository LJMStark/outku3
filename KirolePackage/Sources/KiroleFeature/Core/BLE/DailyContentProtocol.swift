import CryptoKit
import Foundation

public struct DailyContentVersion: Sendable, Equatable, Codable {
    public let epoch: UInt32
    public let revision: UInt32

    public init(epoch: UInt32, revision: UInt32) {
        self.epoch = epoch
        self.revision = revision
    }
}

public struct DailyContentCommittedState: Sendable, Equatable, Codable {
    public let version: DailyContentVersion
    public let contentCRC32: UInt32

    public init(version: DailyContentVersion, contentCRC32: UInt32) {
        self.version = version
        self.contentCRC32 = contentCRC32
    }
}

public struct DailyContentDate: Sendable, Equatable, Codable {
    public let year: UInt16
    public let month: UInt8
    public let day: UInt8

    public init(year: UInt16, month: UInt8, day: UInt8) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = UInt16(clamping: components.year ?? 1970)
        month = UInt8(clamping: components.month ?? 1)
        day = UInt8(clamping: components.day ?? 1)
    }
}

public struct DailyContentEvent: Sendable, Equatable, Codable {
    public let eventID: String
    public let startTimestamp: UInt64
    public let endTimestamp: UInt64
    public let isAllDay: Bool
    public let title: String
    public let detail: String
    public let category: EventCategory
    public let companionDialogue: String
    public let supportText: String

    public init(
        eventID: String,
        startTimestamp: UInt64,
        endTimestamp: UInt64,
        isAllDay: Bool,
        title: String,
        detail: String,
        category: EventCategory,
        companionDialogue: String,
        supportText: String
    ) {
        self.eventID = eventID
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.isAllDay = isAllDay
        self.title = title
        self.detail = detail
        self.category = category
        self.companionDialogue = companionDialogue
        self.supportText = supportText
    }
}

public struct DailyContentPackage: Sendable, Equatable, Codable {
    public let localDate: DailyContentDate
    public let morningDialogue: String
    public let idleDialogue: String
    public let closingDialogue: String
    public let daySummary: String
    public let screensaverQuote: String
    public let screensaverAuthor: String
    public let settlementReview: String
    public let settlementQuote: String
    public let events: [DailyContentEvent]

    public init(
        localDate: DailyContentDate,
        morningDialogue: String,
        idleDialogue: String,
        closingDialogue: String,
        daySummary: String,
        screensaverQuote: String,
        screensaverAuthor: String,
        settlementReview: String,
        settlementQuote: String,
        events: [DailyContentEvent]
    ) {
        self.localDate = localDate
        self.morningDialogue = morningDialogue
        self.idleDialogue = idleDialogue
        self.closingDialogue = closingDialogue
        self.daySummary = daySummary
        self.screensaverQuote = screensaverQuote
        self.screensaverAuthor = screensaverAuthor
        self.settlementReview = settlementReview
        self.settlementQuote = settlementQuote
        self.events = events
    }
}

public struct DailyContentTransaction: Sendable, Equatable, Codable {
    public let version: DailyContentVersion
    public let package: DailyContentPackage

    public init(version: DailyContentVersion, package: DailyContentPackage) {
        self.version = version
        self.package = package
    }
}

public enum DailyContentCommitResult: UInt8, Sendable, Equatable, Codable {
    case committed = 0x00
    case invalidPayload = 0x01
    case checksumMismatch = 0x02
    case capacityExceeded = 0x03
    case unsupportedVersion = 0x04
    case internalError = 0xFF
}

public struct DailyContentCommitAcknowledgement: Sendable, Equatable, Codable {
    public let version: DailyContentVersion
    public let result: DailyContentCommitResult
    public let contentCRC32: UInt32

    public init(
        version: DailyContentVersion,
        result: DailyContentCommitResult,
        contentCRC32: UInt32
    ) {
        self.version = version
        self.result = result
        self.contentCRC32 = contentCRC32
    }
}

public enum DailyContentCodecError: Error, Equatable, Sendable {
    case invalidVersion
    case invalidDate
    case invalidEventID
    case invalidCategory(UInt8)
    case invalidCommitResult(UInt8)
    case unsupportedSubVersion(UInt8)
    case recordCountOverflow
    case truncated(field: String)
    case fieldTooLong(field: String, length: Int, max: Int)
    case invalidUTF8(field: String)
    case checksumMismatch(expected: UInt32, actual: UInt32)
    case trailingBytes(Int)
}

/// `0x24` always carries one complete replacement for a single local date. Packetization may split
/// the bytes, but firmware exposes the package only after the final CRC and capacity checks pass.
public enum DailyContentCodec {
    public static let subVersion: UInt8 = 0x01
    public static let maxEventIDBytes = 255
    public static let maxTitleBytes = 80
    public static let maxDetailBytes = 180
    public static let maxDialogueBytes = DayPackTextBudget.petDialogue
    public static let maxSupportTextBytes = DayPackTextBudget.eventSupportText

    public static func encodeTransaction(_ transaction: DailyContentTransaction) throws -> Data {
        try validate(version: transaction.version)
        try validate(date: transaction.package.localDate)
        guard transaction.package.events.count <= Int(UInt32.max) else {
            throw DailyContentCodecError.recordCountOverflow
        }

        var payload = Data()
        payload.append(subVersion)
        payload.appendBigEndian(transaction.version.epoch)
        payload.appendBigEndian(transaction.version.revision)
        payload.appendBigEndian(transaction.package.localDate.year)
        payload.append(transaction.package.localDate.month)
        payload.append(transaction.package.localDate.day)
        payload.appendString(transaction.package.morningDialogue, maxLength: maxDialogueBytes)
        payload.appendString(transaction.package.idleDialogue, maxLength: maxDialogueBytes)
        payload.appendString(transaction.package.closingDialogue, maxLength: maxDialogueBytes)
        payload.appendString(transaction.package.daySummary, maxLength: DayPackTextBudget.daySummary)
        payload.appendString(transaction.package.screensaverQuote, maxLength: 180)
        payload.appendString(transaction.package.screensaverAuthor, maxLength: 40)
        payload.appendString(
            transaction.package.settlementReview,
            maxLength: DayPackTextBudget.settlementReview
        )
        payload.appendString(
            transaction.package.settlementQuote,
            maxLength: DayPackTextBudget.settlementQuote
        )
        payload.appendBigEndian(UInt32(transaction.package.events.count))

        var seenEventIDs: Set<String> = []
        for event in transaction.package.events {
            let eventID = event.eventID.asciiSanitizedForEInk()
            guard !eventID.isEmpty,
                  eventID.utf8.count <= maxEventIDBytes,
                  seenEventIDs.insert(eventID).inserted else {
                throw DailyContentCodecError.invalidEventID
            }
            payload.appendString(eventID, maxLength: maxEventIDBytes)
            payload.appendBigEndian(event.startTimestamp)
            payload.appendBigEndian(event.endTimestamp)
            payload.append(event.isAllDay ? 0x01 : 0x00)
            payload.appendString(
                event.title,
                maxLength: maxTitleBytes,
                fallbackIfSanitizedEmpty: "Event"
            )
            payload.appendString(event.detail, maxLength: maxDetailBytes)
            payload.append(event.category.rawValue)
            payload.appendString(event.companionDialogue, maxLength: maxDialogueBytes)
            payload.appendString(event.supportText, maxLength: maxSupportTextBytes)
        }

        payload.appendBigEndian(CRC32.ieee(payload))
        return payload
    }

    public static func decodeTransaction(_ payload: Data) throws -> DailyContentTransaction {
        guard payload.count >= 21 else {
            throw DailyContentCodecError.truncated(field: "transaction")
        }
        let crcOffset = payload.count - 4
        let body = payload.subdata(in: 0..<crcOffset)
        let expectedCRC = payload.bigEndianUInt32(at: crcOffset)
        let actualCRC = CRC32.ieee(body)
        guard expectedCRC == actualCRC else {
            throw DailyContentCodecError.checksumMismatch(
                expected: expectedCRC,
                actual: actualCRC
            )
        }

        var reader = DailyContentReader(data: body)
        let receivedSubVersion = try reader.readByte(field: "subVersion")
        guard receivedSubVersion == subVersion else {
            throw DailyContentCodecError.unsupportedSubVersion(receivedSubVersion)
        }
        let version = DailyContentVersion(
            epoch: try reader.readUInt32(field: "epoch"),
            revision: try reader.readUInt32(field: "revision")
        )
        try validate(version: version)
        let localDate = DailyContentDate(
            year: try reader.readUInt16(field: "year"),
            month: try reader.readByte(field: "month"),
            day: try reader.readByte(field: "day")
        )
        try validate(date: localDate)
        let morningDialogue = try reader.readString(
            field: "morningDialogue", max: maxDialogueBytes
        )
        let idleDialogue = try reader.readString(
            field: "idleDialogue", max: maxDialogueBytes
        )
        let closingDialogue = try reader.readString(
            field: "closingDialogue", max: maxDialogueBytes
        )
        let daySummary = try reader.readString(
            field: "daySummary", max: DayPackTextBudget.daySummary
        )
        let screensaverQuote = try reader.readString(field: "screensaverQuote", max: 180)
        let screensaverAuthor = try reader.readString(field: "screensaverAuthor", max: 40)
        let settlementReview = try reader.readString(
            field: "settlementReview", max: DayPackTextBudget.settlementReview
        )
        let settlementQuote = try reader.readString(
            field: "settlementQuote", max: DayPackTextBudget.settlementQuote
        )
        let eventCount = try reader.readUInt32(field: "eventCount")
        var events: [DailyContentEvent] = []
        var seenEventIDs: Set<String> = []
        for index in 0..<eventCount {
            let field = "events[\(index)]"
            let eventID = try reader.readString(
                field: "\(field).eventID", max: maxEventIDBytes
            )
            guard !eventID.isEmpty, seenEventIDs.insert(eventID).inserted else {
                throw DailyContentCodecError.invalidEventID
            }
            let startTimestamp = try reader.readUInt64(field: "\(field).startTimestamp")
            let endTimestamp = try reader.readUInt64(field: "\(field).endTimestamp")
            let allDay = try reader.readByte(field: "\(field).isAllDay")
            guard allDay <= 1 else { throw DailyContentCodecError.invalidDate }
            let title = try reader.readString(field: "\(field).title", max: maxTitleBytes)
            let detail = try reader.readString(field: "\(field).detail", max: maxDetailBytes)
            let categoryByte = try reader.readByte(field: "\(field).category")
            guard let category = EventCategory(rawValue: categoryByte) else {
                throw DailyContentCodecError.invalidCategory(categoryByte)
            }
            events.append(DailyContentEvent(
                eventID: eventID,
                startTimestamp: startTimestamp,
                endTimestamp: endTimestamp,
                isAllDay: allDay == 1,
                title: title,
                detail: detail,
                category: category,
                companionDialogue: try reader.readString(
                    field: "\(field).companionDialogue", max: maxDialogueBytes
                ),
                supportText: try reader.readString(
                    field: "\(field).supportText", max: maxSupportTextBytes
                )
            ))
        }
        try reader.requireEnd()
        return DailyContentTransaction(
            version: version,
            package: DailyContentPackage(
                localDate: localDate,
                morningDialogue: morningDialogue,
                idleDialogue: idleDialogue,
                closingDialogue: closingDialogue,
                daySummary: daySummary,
                screensaverQuote: screensaverQuote,
                screensaverAuthor: screensaverAuthor,
                settlementReview: settlementReview,
                settlementQuote: settlementQuote,
                events: events
            )
        )
    }

    public static func committedState(
        for transaction: DailyContentTransaction
    ) throws -> DailyContentCommittedState {
        let payload = try encodeTransaction(transaction)
        return DailyContentCommittedState(
            version: transaction.version,
            contentCRC32: payload.bigEndianUInt32(at: payload.count - 4)
        )
    }

    public static func encodeAcknowledgement(
        _ acknowledgement: DailyContentCommitAcknowledgement
    ) -> Data {
        var payload = Data([subVersion])
        payload.appendBigEndian(acknowledgement.version.epoch)
        payload.appendBigEndian(acknowledgement.version.revision)
        payload.append(acknowledgement.result.rawValue)
        payload.appendBigEndian(acknowledgement.contentCRC32)
        return payload
    }

    public static func decodeAcknowledgement(
        _ payload: Data
    ) throws -> DailyContentCommitAcknowledgement {
        var reader = DailyContentReader(data: payload)
        let receivedSubVersion = try reader.readByte(field: "subVersion")
        guard receivedSubVersion == subVersion else {
            throw DailyContentCodecError.unsupportedSubVersion(receivedSubVersion)
        }
        let version = DailyContentVersion(
            epoch: try reader.readUInt32(field: "epoch"),
            revision: try reader.readUInt32(field: "revision")
        )
        try validate(version: version)
        let resultByte = try reader.readByte(field: "result")
        guard let result = DailyContentCommitResult(rawValue: resultByte) else {
            throw DailyContentCodecError.invalidCommitResult(resultByte)
        }
        let contentCRC32 = try reader.readUInt32(field: "contentCRC32")
        try reader.requireEnd()
        return DailyContentCommitAcknowledgement(
            version: version,
            result: result,
            contentCRC32: contentCRC32
        )
    }

    private static func validate(version: DailyContentVersion) throws {
        guard version.epoch != 0, version.revision != 0 else {
            throw DailyContentCodecError.invalidVersion
        }
    }

    private static func validate(date: DailyContentDate) throws {
        guard date.year >= 2000,
              (1...12).contains(date.month),
              (1...31).contains(date.day) else {
            throw DailyContentCodecError.invalidDate
        }
    }
}

public enum DailyContentSource {
    /// 当天内容包（`0x24`）单次事务的日程上限（2026-08-04 客户拍板）。超出静默截断，App 不做
    /// 任何 UI 提示。与任务库的 `TaskLibraryMembership.maxRecords` 今天同值，但**刻意不共享
    /// 常量**——两个内容域独立版本化、独立持久化、协议 §4.22 与 §4.23 分开写，共享会暗示一种
    /// 不存在的耦合。设备侧仍不得自行截断（放不下回 `capacityExceeded`）。
    public static let maxEvents = 20

    /// 当天日程的有序集合。先按开始时间排序**再**截断，所以留下的是当天最早的 20 条；
    /// 反过来会截出一批任意日程再排序。
    ///
    /// 截断必须落在这一层：`DailyContentPackageGenerator` 用本函数造 `preparedEventSummaries`
    /// 传给 `DayPackGenerator.generateDayPack`，而后者会自己重新筛一遍当天日程。只在更上层截断
    /// 会让两条长度不同的列表进入结算文案，概览统计与实际列表对不上。
    public static func todayEvents(
        from events: [CalendarEvent],
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        Array(
            events
                .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
                .sorted {
                    if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
                    return $0.id < $1.id
                }
                .prefix(maxEvents)
        )
    }

    public static func eventIdentifier(_ event: CalendarEvent) -> String {
        let sanitized = event.id.asciiSanitizedForEInk()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !sanitized.isEmpty, sanitized.utf8.count <= DailyContentCodec.maxEventIDBytes {
            return sanitized
        }
        return SHA256.hash(data: Data(event.id.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func eventFingerprint(_ event: CalendarEvent) -> String {
        digest([
            event.id,
            event.title,
            String(event.startTime.timeIntervalSinceReferenceDate.bitPattern),
            String(event.endTime.timeIntervalSinceReferenceDate.bitPattern),
            event.description ?? "",
            event.location ?? "",
            event.isAllDay ? "1" : "0",
        ])
    }

    public static func personaFingerprint(
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> String {
        let profileContext = "|\(userProfile.intimacyStage.rawValue)"
            + "|\(userProfile.workType.rawValue)|"
            + userProfile.primaryGoals.map(\.rawValue).joined(separator: ",")
        if let id = userProfile.customCompanionId {
            let revision = customCompanions.first { $0.id == id }?
                .updatedAt.timeIntervalSinceReferenceDate.bitPattern ?? 0
            return "custom|\(id.uuidString)|\(revision)\(profileContext)"
        }
        return "built-in|\(userProfile.companionCharacter.rawValue)\(profileContext)"
    }

    public static func eventFingerprints(
        _ events: [CalendarEvent],
        at date: Date,
        calendar: Calendar = .current
    ) -> [String: String] {
        var result: [String: String] = [:]
        for event in todayEvents(from: events, at: date, calendar: calendar) {
            let identifier = eventIdentifier(event)
            if result[identifier] == nil {
                result[identifier] = eventFingerprint(event)
            }
        }
        return result
    }

    public static func sourceFingerprint(
        events: [CalendarEvent],
        at date: Date,
        calendar: Calendar = .current,
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> String {
        let localDate = DailyContentDate(date: date, calendar: calendar)
        let eventParts = todayEvents(from: events, at: date, calendar: calendar).flatMap {
            [eventIdentifier($0), eventFingerprint($0)]
        }
        return digest([
            String(localDate.year),
            String(localDate.month),
            String(localDate.day),
            personaFingerprint(
                userProfile: userProfile,
                customCompanions: customCompanions
            ),
        ] + eventParts)
    }

    public static func packageSourceFingerprint(
        events: [CalendarEvent],
        tasks: [TaskItem],
        pet: Pet,
        usageDays: Int,
        sceneID: String,
        focusMinutes: Int,
        at date: Date,
        calendar: Calendar = .current,
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> String {
        let taskParts = tasks.enumerated().flatMap { index, task in
            [
                String(index), task.id, task.title, task.notes ?? "",
                task.isCompleted ? "1" : "0", task.pendingDeletion ? "1" : "0",
                task.dueDate.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "-",
                task.todayDisplayDate.map { String($0.timeIntervalSinceReferenceDate.bitPattern) }
                    ?? "-",
            ]
        }
        return digest([
            sourceFingerprint(
                events: events,
                at: date,
                calendar: calendar,
                userProfile: userProfile,
                customCompanions: customCompanions
            ),
            pet.name,
            pet.mood.rawValue,
            String(usageDays),
            sceneID,
            String(focusMinutes),
        ] + taskParts)
    }

    public static func staticCopyFingerprint(
        eventTitles: [String],
        tasks: [TaskItem],
        pet: Pet,
        usageDays: Int,
        sceneID: String,
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> String {
        digest([
            personaFingerprint(userProfile: userProfile, customCompanions: customCompanions),
            pet.name,
            pet.mood.rawValue,
            String(usageDays),
            sceneID,
        ] + eventTitles
            + tasks.filter { !$0.isCompleted && !$0.pendingDeletion }.map(\.title))
    }

    public static func eventDialogueFingerprint(
        pet: Pet,
        userProfile: UserProfile,
        customCompanions: [CustomCompanion]
    ) -> String {
        digest([
            personaFingerprint(userProfile: userProfile, customCompanions: customCompanions),
            pet.name,
            pet.mood.rawValue,
        ])
    }

    public static func makeEvent(
        from event: CalendarEvent,
        summary: EventSummary,
        companionDialogue: String
    ) -> DailyContentEvent {
        DailyContentEvent(
            eventID: eventIdentifier(event),
            startTimestamp: UInt64(max(0, event.startTime.timeIntervalSince1970)),
            endTimestamp: UInt64(max(0, event.endTime.timeIntervalSince1970)),
            isAllDay: event.isAllDay,
            title: event.title,
            detail: event.description ?? "",
            category: summary.category,
            companionDialogue: companionDialogue,
            supportText: summary.supportText
        )
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

private struct DailyContentReader {
    let data: Data
    private(set) var offset = 0

    mutating func readByte(field: String) throws -> UInt8 {
        guard offset < data.count else {
            throw DailyContentCodecError.truncated(field: field)
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16(field: String) throws -> UInt16 {
        guard offset + 2 <= data.count else {
            throw DailyContentCodecError.truncated(field: field)
        }
        defer { offset += 2 }
        return data.bigEndianUInt16(at: offset)
    }

    mutating func readUInt32(field: String) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw DailyContentCodecError.truncated(field: field)
        }
        defer { offset += 4 }
        return data.bigEndianUInt32(at: offset)
    }

    mutating func readUInt64(field: String) throws -> UInt64 {
        guard offset + 8 <= data.count else {
            throw DailyContentCodecError.truncated(field: field)
        }
        defer { offset += 8 }
        return data.bigEndianUInt64(at: offset)
    }

    mutating func readString(field: String, max: Int) throws -> String {
        let length = Int(try readByte(field: "\(field).length"))
        guard length <= max else {
            throw DailyContentCodecError.fieldTooLong(field: field, length: length, max: max)
        }
        guard offset + length <= data.count else {
            throw DailyContentCodecError.truncated(field: field)
        }
        let bytes = data.subdata(in: offset..<(offset + length))
        offset += length
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw DailyContentCodecError.invalidUTF8(field: field)
        }
        return value
    }

    func requireEnd() throws {
        guard offset == data.count else {
            throw DailyContentCodecError.trailingBytes(data.count - offset)
        }
    }
}

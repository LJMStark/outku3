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
                EventSummary(time: "09:30", endTime: "10:00", title: "HW Sync", description: "Bring the logic analyzer.", category: .meetings),
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

struct SimulatedHardware {
    private var packetAssembler = BLEPacketAssembler()

    mutating func receiveSingleAppPacket(_ data: Data) throws -> SimulatedAppPacket {
        if data.first == 0xAA {
            throw SimulationError.developmentDisplayCommandNotStandard
        }

        if let assembled = packetAssembler.append(packetData: data) {
            return SimulatedAppPacket(type: assembled.type, payload: assembled.payload, transport: .chunked)
        }

        if packetAssembler.isPotentialChunk(packetData: data) {
            throw SimulationError.incompleteChunkedMessage
        }

        return try Self.parseSimpleAppPacket(data)
    }

    mutating func receiveAppPacket(_ data: Data) throws -> SimulatedAppPacket? {
        if data.first == 0xAA {
            throw SimulationError.developmentDisplayCommandNotStandard
        }

        if let assembled = packetAssembler.append(packetData: data) {
            return SimulatedAppPacket(type: assembled.type, payload: assembled.payload, transport: .chunked)
        }

        if packetAssembler.isPotentialChunk(packetData: data) {
            return nil
        }

        return try Self.parseSimpleAppPacket(data)
    }

    mutating func receiveAppPacketStream(_ packets: [Data]) throws -> SimulatedAppPacket? {
        var result: SimulatedAppPacket?
        for packet in packets {
            if let parsed = try receiveAppPacket(packet) {
                result = parsed
            }
        }
        return result
    }

    // 旧 `parseDevelopmentDisplayPacket`（解析 0xAA 开发命令）已于 v2.5.11 移除：屏保（0x16）与
    // 场景解锁（0x17）均已升级为业务帧，不再有 0xAA 命令。`receiveSingleAppPacket` / `receiveAppPacket`
    // 仍以 `developmentDisplayCommandNotStandard` 守卫拒收任何残留 0xAA 包。

    private static func parseSimpleAppPacket(_ data: Data) throws -> SimulatedAppPacket {
        guard data.count >= 3 else {
            throw SimulationError.truncatedPacket
        }

        let length = Int(data[1]) << 8 | Int(data[2])
        guard data.count == 3 + length else {
            throw SimulationError.lengthMismatch(expected: length, actual: data.count - 3)
        }

        return SimulatedAppPacket(
            type: data[0],
            payload: length > 0 ? data.subdata(in: 3..<data.count) : Data(),
            transport: .simple
        )
    }
}

/// v2.5.24 分包帧（11 字节头）的固件视角镜像重组器（协议 §3.2）。
/// 刻意不复用生产 `BLEPacketAssembler`——逐字节手写解析才能镜像固件的实现视角：
/// 11 字节头逐字段读取、`count == 11 + len` 的 requireEnd 纪律、逐片 CRC16 校验、
/// 跨片 type/messageId/total 一致性检查、按 Seq 升序拼接。
/// 生产 Assembler 的 256KiB 入站帽只管 Device→App 方向，本重组器不设帽——
/// 专用于仿真 App→Device 的 ≤1MiB CustomAvatarFrame(0x15) 大载荷传输。
struct SimulatedFirmwareChunkReassembler {
    private var expectedType: UInt8?
    private var expectedMessageId: UInt16?
    private var expectedTotal: Int?
    private var chunks: [Int: Data] = [:]

    /// 返回 nil 表示消息尚未收齐；收齐后返回完整重组 payload。
    mutating func receive(_ packet: Data) throws -> Data? {
        guard packet.count >= 11 else {
            throw SimulationError.truncatedPacket
        }

        let type = packet[0]
        let messageId = UInt16(packet[1]) << 8 | UInt16(packet[2])
        let seq = Int(packet[3]) << 8 | Int(packet[4])
        let total = Int(packet[5]) << 8 | Int(packet[6])
        let length = Int(packet[7]) << 8 | Int(packet[8])
        let crc = UInt16(packet[9]) << 8 | UInt16(packet[10])

        // requireEnd 纪律：分包帧不允许尾部多余字节。
        guard packet.count == 11 + length else {
            throw SimulationError.lengthMismatch(expected: length, actual: packet.count - 11)
        }
        guard total > 0, seq < total else {
            throw SimulationError.chunkHeaderMismatch
        }

        let chunk = packet.subdata(in: 11..<packet.count)
        guard CRC16.ccittFalse(chunk) == crc else {
            throw SimulationError.chunkCRCMismatch
        }

        if let expectedType, let expectedMessageId, let expectedTotal {
            guard type == expectedType, messageId == expectedMessageId, total == expectedTotal else {
                throw SimulationError.chunkHeaderMismatch
            }
        } else {
            expectedType = type
            expectedMessageId = messageId
            expectedTotal = total
        }

        chunks[seq] = chunk
        guard chunks.count == total else { return nil }

        var payload = Data()
        for index in 0..<total {
            guard let part = chunks[index] else {
                throw SimulationError.chunkHeaderMismatch
            }
            payload.append(part)
        }
        return payload
    }
}

struct SimulatedAppPacket {
    let type: UInt8
    let payload: Data
    let transport: SimulatedTransport

    func parsePetStatus() throws -> SimulatedPetStatus {
        try requireType(BLEDataType.petStatus)
        var reader = PayloadReader(data: payload)
        let name = try reader.readString()
        let moodByte = try reader.readByte()
        let characterId = try reader.readString()
        // v2.5.32: CustomActive tail byte (mirror encodePetStatus).
        let customActive = try reader.readBool()
        try reader.requireEnd()
        return SimulatedPetStatus(
            name: name,
            moodByte: moodByte,
            characterId: characterId,
            customActive: customActive
        )
    }

    func parseTaskList() throws -> SimulatedTaskList {
        try requireType(BLEDataType.taskList)
        var reader = PayloadReader(data: payload)
        let count = Int(try reader.readByte())
        var tasks: [SimulatedTaskList.Task] = []
        for _ in 0..<count {
            tasks.append(.init(title: try reader.readString(), isCompleted: try reader.readBool()))
        }
        try reader.requireEnd()
        return SimulatedTaskList(tasks: tasks)
    }

    func parseSchedule() throws -> SimulatedSchedule {
        try requireType(BLEDataType.schedule)
        var reader = PayloadReader(data: payload)
        let count = Int(try reader.readByte())
        var events: [SimulatedSchedule.Event] = []
        for _ in 0..<count {
            let title = try reader.readString()
            let startTime = try reader.readFixedUTF8(length: 5)
            events.append(.init(title: title, startTime: startTime))
        }
        try reader.requireEnd()
        return SimulatedSchedule(events: events)
    }

    func parseWeather() throws -> SimulatedWeather {
        try requireType(BLEDataType.weather)
        var reader = PayloadReader(data: payload)
        let temperature = Int(Int8(bitPattern: try reader.readByte()))
        let condition = try reader.readString()
        // v2.5.9: HighTemp / LowTemp appended after Condition (mirror encodeWeather).
        let highTemp = Int(Int8(bitPattern: try reader.readByte()))
        let lowTemp = Int(Int8(bitPattern: try reader.readByte()))
        try reader.requireEnd()
        return SimulatedWeather(temperature: temperature, condition: condition, highTemp: highTemp, lowTemp: lowTemp)
    }

    func parseCurrentTime() throws -> SimulatedCurrentTime {
        try requireType(BLEDataType.time)
        var reader = PayloadReader(data: payload)
        let year = 2000 + Int(try reader.readByte())
        let month = try reader.readByte()
        let day = try reader.readByte()
        let hour = try reader.readByte()
        let minute = try reader.readByte()
        let second = try reader.readByte()
        try reader.requireEnd()
        return SimulatedCurrentTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    func parseDayPack() throws -> SimulatedDayPack {
        try requireType(BLEDataType.dayPack)
        var reader = PayloadReader(data: payload)
        let year = 2000 + Int(try reader.readByte())
        let month = Int(try reader.readByte())
        let day = Int(try reader.readByte())
        let deviceMode = try reader.readByte() == 0x00 ? DeviceMode.interactive : .focus
        let focusChallengeEnabled = try reader.readBool()
        let petDialogue = try reader.readString()

        let eventCount = Int(try reader.readByte())
        var events: [SimulatedDayPack.Event] = []
        for _ in 0..<eventCount {
            events.append(.init(
                time: try reader.readString(),
                title: try reader.readString(),
                description: try reader.readString(),
                // v2.5.27: per-event Category byte (mirror encodeDayPack).
                category: try reader.readByte(),
                // v2.5.30: per-event EndTime string after Category (mirror encodeDayPack).
                endTime: try reader.readString()
            ))
        }

        let taskCount = Int(try reader.readByte())
        var topTasks: [SimulatedDayPack.TopTask] = []
        for _ in 0..<taskCount {
            topTasks.append(.init(
                id: try reader.readString(),
                title: try reader.readString(),
                isCompleted: try reader.readBool(),
                priority: try reader.readByte()
            ))
        }

        let settlement = SimulatedDayPack.Settlement(
            tasksCompleted: Int(try reader.readByte()),
            tasksTotal: Int(try reader.readByte()),
            pointsEarned: Int(try reader.readUInt16BE()),
            totalFocusMinutes: Int(try reader.readUInt16BE()),
            focusSessionCount: Int(try reader.readByte()),
            longestFocusMinutes: Int(try reader.readUInt16BE()),
            interruptionCount: Int(try reader.readByte())
        )
        // v2.5.7/v2.5.8: DaySummary then FirstUp (mirror encodeDayPack).
        let daySummary = try reader.readString()
        let firstUp = try reader.readString()
        // v2.5.30/v2.5.31: settlement page texts are the tail DayPack fields — SettlementReview,
        // then SettlementQuote as the final field (mirror encodeDayPack).
        let settlementReview = try reader.readString()
        let settlementQuote = try reader.readString()
        try reader.requireEnd()

        return SimulatedDayPack(
            date: (year, month, day),
            deviceMode: deviceMode,
            focusChallengeEnabled: focusChallengeEnabled,
            petDialogue: petDialogue,
            daySummary: daySummary,
            firstUp: firstUp,
            settlementReview: settlementReview,
            settlementQuote: settlementQuote,
            events: events,
            topTasks: topTasks,
            settlement: settlement
        )
    }

    func parseTaskInPage() throws -> SimulatedTaskInPage {
        try requireType(BLEDataType.taskInPage)
        var reader = PayloadReader(data: payload)
        let taskId = try reader.readString()
        let taskTitle = try reader.readString()
        let taskDescription = try reader.readString()
        let encouragement = try reader.readString()
        let focusChallengeActive = try reader.readBool()
        try reader.requireEnd()
        return SimulatedTaskInPage(
            taskId: taskId,
            taskTitle: taskTitle,
            taskDescription: taskDescription,
            encouragement: encouragement,
            focusChallengeActive: focusChallengeActive
        )
    }

    func parseDeviceMode() throws -> DeviceMode {
        try requireType(BLEDataType.deviceMode)
        var reader = PayloadReader(data: payload)
        let byte = try reader.readByte()
        try reader.requireEnd()
        return byte == 0x00 ? .interactive : .focus
    }

    func parseSmartReminder() throws -> SimulatedSmartReminder {
        try requireType(BLEDataType.smartReminder)
        var reader = PayloadReader(data: payload)
        let text = try reader.readString()
        let urgencyByte = try reader.readByte()
        let petMoodByte = try reader.readByte()
        try reader.requireEnd()
        guard let urgency = ReminderUrgency(rawValue: urgencyByte) else {
            throw SimulationError.invalidEnumValue
        }
        return SimulatedSmartReminder(text: text, urgency: urgency, petMoodByte: petMoodByte)
    }

    func parseEventLogRequestSince() throws -> UInt32 {
        try requireType(BLEDataType.eventLogRequest)
        var reader = PayloadReader(data: payload)
        let timestamp = try reader.readUInt32BE()
        try reader.requireEnd()
        return timestamp
    }

    private func requireType(_ expectedType: BLEDataType) throws {
        guard type == expectedType.rawValue else {
            throw SimulationError.unexpectedType(expected: expectedType.rawValue, actual: type)
        }
    }
}

enum SimulatedTransport {
    case simple
    case chunked
}

private struct PayloadReader {
    private let data: Data
    private var cursor = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readByte() throws -> UInt8 {
        guard cursor < data.count else {
            throw SimulationError.truncatedPayload
        }
        let byte = data[cursor]
        cursor += 1
        return byte
    }

    mutating func expectByte(_ expected: UInt8) throws {
        let byte = try readByte()
        guard byte == expected else {
            throw SimulationError.unexpectedType(expected: expected, actual: byte)
        }
    }

    mutating func readBool() throws -> Bool {
        try readByte() != 0x00
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let high = UInt16(try readByte())
        let low = UInt16(try readByte())
        return high << 8 | low
    }

    mutating func readUInt32BE() throws -> UInt32 {
        let b0 = UInt32(try readByte())
        let b1 = UInt32(try readByte())
        let b2 = UInt32(try readByte())
        let b3 = UInt32(try readByte())
        return b0 << 24 | b1 << 16 | b2 << 8 | b3
    }

    mutating func readString() throws -> String {
        let length = Int(try readByte())
        return try readFixedUTF8(length: length)
    }

    mutating func readFixedUTF8(length: Int) throws -> String {
        guard cursor + length <= data.count else {
            throw SimulationError.truncatedPayload
        }
        let stringData = data.subdata(in: cursor..<(cursor + length))
        cursor += length
        guard let string = String(data: stringData, encoding: .utf8) else {
            throw SimulationError.invalidUTF8
        }
        return string
    }

    func requireEnd() throws {
        guard cursor == data.count else {
            throw SimulationError.trailingBytes
        }
    }
}

struct SimulatedPetStatus {
    let name: String
    let moodByte: UInt8?
    let characterId: String
    let customActive: Bool
}

struct SimulatedTaskList {
    struct Task {
        let title: String
        let isCompleted: Bool
    }

    let tasks: [Task]
}

struct SimulatedSchedule {
    struct Event {
        let title: String
        let startTime: String
    }

    let events: [Event]
}

struct SimulatedWeather {
    let temperature: Int
    let condition: String
    let highTemp: Int
    let lowTemp: Int
}

struct SimulatedCurrentTime {
    let year: Int
    let month: UInt8
    let day: UInt8
    let hour: UInt8
    let minute: UInt8
    let second: UInt8
}

struct SimulatedDayPack {
    struct TopTask {
        let id: String
        let title: String
        let isCompleted: Bool
        let priority: UInt8
    }

    struct Settlement {
        let tasksCompleted: Int
        let tasksTotal: Int
        let pointsEarned: Int
        let totalFocusMinutes: Int
        let focusSessionCount: Int
        let longestFocusMinutes: Int
        let interruptionCount: Int
    }

    struct Event {
        let time: String
        let title: String
        let description: String
        let category: UInt8
        let endTime: String
    }

    let date: (year: Int, month: Int, day: Int)
    let deviceMode: DeviceMode
    let focusChallengeEnabled: Bool
    let petDialogue: String
    let daySummary: String
    let firstUp: String
    let settlementReview: String
    let settlementQuote: String
    let events: [Event]
    let topTasks: [TopTask]
    let settlement: Settlement
}

struct SimulatedTaskInPage {
    let taskId: String
    let taskTitle: String
    let taskDescription: String
    let encouragement: String
    let focusChallengeActive: Bool
}

struct SimulatedSmartReminder {
    let text: String
    let urgency: ReminderUrgency
    let petMoodByte: UInt8?
}

enum SimulationError: Error, Equatable {
    case truncatedPacket
    case truncatedPayload
    case lengthMismatch(expected: Int, actual: Int)
    case incompleteChunkedMessage
    case trailingBytes
    case invalidUTF8
    case invalidEnumValue
    case developmentDisplayCommandNotStandard
    case invalidSecureHandshake
    case unexpectedType(expected: UInt8, actual: UInt8)
    case chunkCRCMismatch
    case chunkHeaderMismatch
}

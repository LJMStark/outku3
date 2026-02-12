import Foundation
import Testing
@testable import KiroFeature

@Suite("BLE Protocol Tests")
struct BLEProtocolTests {

    // MARK: - CRC16 Tests

    @Test("CRC16-CCITT-FALSE known vector")
    func crc16KnownVector() throws {
        let data = Data("123456789".utf8)
        let crc = CRC16.ccittFalse(data)
        #expect(crc == 0x29B1)
    }

    // MARK: - BLEPacketizer & Assembler Tests

    @Test("Packetize and assemble round-trip")
    func packetizeAndAssemble() throws {
        let payload = Data((0..<50).map { UInt8($0) })
        let packets = try BLEPacketizer.packetize(
            type: 0x10,
            messageId: 0x1234,
            payload: payload,
            maxChunkSize: 8
        )

        let assembler = BLEPacketAssembler()
        var result: BLEReceivedMessage?
        for packet in packets {
            if let message = assembler.append(packetData: packet) {
                result = message
            }
        }

        #expect(result?.type == 0x10)
        #expect(result?.payload == payload)
    }

    @Test("BLEPacketAssembler rejects packet shorter than header")
    func assemblerRejectsTooShort() {
        let assembler = BLEPacketAssembler()
        let shortData = Data([0x01, 0x02, 0x03])
        let result = assembler.append(packetData: shortData)
        #expect(result == nil)
    }

    @Test("BLEPacketizer rejects zero chunk size")
    func packetizerRejectsZeroChunkSize() {
        #expect(throws: BLEPacketError.self) {
            _ = try BLEPacketizer.packetize(
                type: 0x01,
                messageId: 1,
                payload: Data([0x01]),
                maxChunkSize: 0
            )
        }
    }

    // MARK: - BLE Sync Policy Tests

    @Test("BLE sync policy day interval")
    func syncPolicyDayInterval() throws {
        let calendar = Calendar.current
        var components = DateComponents(year: 2026, month: 2, day: 4, hour: 10, minute: 0)
        let lastSync = calendar.date(from: components)!

        components.hour = 10
        components.minute = 30
        let now = calendar.date(from: components)!

        let policy = BLESyncPolicy()
        let shouldSync = policy.shouldSync(now: now, lastSync: lastSync, contentChanged: false, force: false)
        #expect(shouldSync == false)

        components.hour = 11
        components.minute = 1
        let later = calendar.date(from: components)!
        let shouldSyncLater = policy.shouldSync(now: later, lastSync: lastSync, contentChanged: false, force: false)
        #expect(shouldSyncLater == true)
    }

    @Test("BLE sync policy night interval")
    func syncPolicyNightInterval() throws {
        let calendar = Calendar.current
        var components = DateComponents(year: 2026, month: 2, day: 4, hour: 23, minute: 30)
        let lastSync = calendar.date(from: components)!

        components.day = 5
        components.hour = 1
        components.minute = 0
        let earlyNight = calendar.date(from: components)!

        let policy = BLESyncPolicy()
        let shouldSyncEarly = policy.shouldSync(now: earlyNight, lastSync: lastSync, contentChanged: false, force: false)
        #expect(shouldSyncEarly == false)

        components.hour = 3
        components.minute = 31
        let laterNight = calendar.date(from: components)!
        let shouldSyncLater = policy.shouldSync(now: laterNight, lastSync: lastSync, contentChanged: false, force: false)
        #expect(shouldSyncLater == true)
    }

    // MARK: - DayPack Fingerprint Tests

    @Test("DayPack fingerprint changes on content change")
    func dayPackFingerprint() throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let settlement = SettlementData(
            tasksCompleted: 1,
            tasksTotal: 3,
            pointsEarned: 10,
            streakDays: 2,
            petMood: "happy",
            summaryMessage: "summary",
            encouragementMessage: "encourage"
        )

        let packA = DayPack(
            date: baseDate,
            weather: WeatherInfo(temperature: 20, highTemp: 25, lowTemp: 15, condition: "Clear", iconName: "Clear"),
            deviceMode: .interactive,
            focusChallengeEnabled: false,
            morningGreeting: "hello",
            dailySummary: "summary",
            firstItem: "task",
            currentScheduleSummary: "2 events",
            topTasks: [TaskSummary(id: "1", title: "A", isCompleted: false, priority: 1, dueTime: "09:00")],
            companionPhrase: "phrase",
            settlementData: settlement
        )

        let packB = DayPack(
            date: baseDate,
            weather: WeatherInfo(temperature: 20, highTemp: 25, lowTemp: 15, condition: "Clear", iconName: "Clear"),
            deviceMode: .interactive,
            focusChallengeEnabled: false,
            morningGreeting: "hello",
            dailySummary: "summary",
            firstItem: "task",
            currentScheduleSummary: "2 events",
            topTasks: [TaskSummary(id: "1", title: "A", isCompleted: false, priority: 1, dueTime: "09:00")],
            companionPhrase: "phrase-updated",
            settlementData: settlement
        )

        #expect(packA.stableFingerprint() != packB.stableFingerprint())
        #expect(packA.stableFingerprint() == packA.stableFingerprint())
    }

    // MARK: - BLESimpleEncoder Tests

    @Test("BLESimpleEncoder produces correct 3-byte header")
    func simpleEncoderProducesCorrectHeader() {
        let payload = Data([0x01, 0x02, 0x03])
        let packet = BLESimpleEncoder.encode(type: 0x10, payload: payload)
        #expect(packet.count == 6)
        #expect(packet[0] == 0x10)
        #expect(packet[1] == 0x00)
        #expect(packet[2] == 0x03)
        #expect(packet[3] == 0x01)
    }

    @Test("BLESimpleEncoder handles empty payload")
    func simpleEncoderHandlesEmptyPayload() {
        let packet = BLESimpleEncoder.encode(type: 0x05, payload: Data())
        #expect(packet.count == 3)
        #expect(packet[0] == 0x05)
        #expect(packet[1] == 0x00)
        #expect(packet[2] == 0x00)
    }

    @Test("BLESimpleEncoder encodes large payload length correctly")
    func simpleEncoderLargePayload() {
        let payload = Data(repeating: 0xAA, count: 300)
        let packet = BLESimpleEncoder.encode(type: 0x01, payload: payload)
        #expect(packet.count == 303)
        #expect(packet[1] == 0x01)
        #expect(packet[2] == 0x2C)
    }

    // MARK: - BLESimpleDecoder Tests

    @Test("BLESimpleDecoder parses valid packet")
    func simpleDecoderParsesValidPacket() {
        var data = Data([0x10, 0x03])
        data.append(contentsOf: [0x01, 0x02, 0x03])
        let message = BLESimpleDecoder.decode(data)
        #expect(message != nil)
        #expect(message?.type == 0x10)
        #expect(message?.payload.count == 3)
        #expect(message?.payload == Data([0x01, 0x02, 0x03]))
    }

    @Test("BLESimpleDecoder handles no-payload packet")
    func simpleDecoderHandlesNoPayload() {
        let data = Data([0x20, 0x00])
        let message = BLESimpleDecoder.decode(data)
        #expect(message != nil)
        #expect(message?.type == 0x20)
        #expect(message?.payload.count == 0)
    }

    @Test("BLESimpleDecoder rejects data too short")
    func simpleDecoderRejectsTooShort() {
        let data = Data([0x10])
        #expect(BLESimpleDecoder.decode(data) == nil)
    }

    @Test("BLESimpleDecoder rejects truncated payload")
    func simpleDecoderRejectsTruncatedPayload() {
        let data = Data([0x10, 0x05, 0x01])
        #expect(BLESimpleDecoder.decode(data) == nil)
    }

    @Test("BLESimpleDecoder rejects empty data")
    func simpleDecoderRejectsEmptyData() {
        #expect(BLESimpleDecoder.decode(Data()) == nil)
    }

    // MARK: - BLESimpleEncoder/Decoder Round-Trip Test

    @Test("BLESimpleEncoder produces well-formed data with verifiable structure")
    func simpleEncoderDecoderRoundTrip() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let encoded = BLESimpleEncoder.encode(type: 0x01, payload: payload)
        #expect(encoded[0] == 0x01)
        let length = UInt16(encoded[1]) << 8 | UInt16(encoded[2])
        #expect(length == 4)
        #expect(encoded.subdata(in: 3..<7) == payload)
    }

    // MARK: - BLEDataEncoder Tests

    @Test("BLEDataEncoder encodePetStatus produces correct format")
    func encodePetStatusFormat() {
        let pet = Pet(name: "Tiko", mood: .happy, stage: .baby, progress: 0.75)
        let data = BLEDataEncoder.encodePetStatus(pet)

        let nameLen = Int(data[0])
        #expect(nameLen == 4)
        let nameBytes = data.subdata(in: 1..<(1 + nameLen))
        #expect(String(data: nameBytes, encoding: .utf8) == "Tiko")

        let moodOffset = 1 + nameLen
        #expect(data[moodOffset] == Character("H").asciiValue!)

        #expect(data[moodOffset + 1] == Character("B").asciiValue!)

        #expect(data[moodOffset + 2] == 75)
    }

    @Test("BLEDataEncoder encodePetStatus clamps progress to 255")
    func encodePetStatusClampsProgress() {
        let pet = Pet(name: "A", progress: 3.0)
        let data = BLEDataEncoder.encodePetStatus(pet)
        let progressOffset = 1 + 1 + 1 + 1
        #expect(data[progressOffset] == 255)
    }

    @Test("BLEDataEncoder encodeTaskList limits to max 10 tasks")
    func encodeTaskListMaxTen() {
        let today = Date()
        let tasks = (0..<15).map { i in
            TaskItem(title: "Task \(i)", dueDate: today)
        }
        let data = BLEDataEncoder.encodeTaskList(tasks)
        #expect(data[0] == 10)
    }

    @Test("BLEDataEncoder encodeTaskList encodes task title and completion")
    func encodeTaskListFormat() {
        let today = Date()
        let tasks = [
            TaskItem(title: "Buy milk", isCompleted: true, dueDate: today),
            TaskItem(title: "Read book", isCompleted: false, dueDate: today),
        ]
        let data = BLEDataEncoder.encodeTaskList(tasks)
        #expect(data[0] == 2)

        let title1 = "Buy milk"
        let title1Data = title1.data(using: .utf8)!
        #expect(data[1] == UInt8(title1Data.count))
        let title1Bytes = data.subdata(in: 2..<(2 + Int(data[1])))
        #expect(String(data: title1Bytes, encoding: .utf8) == title1)
        let completionOffset1 = 2 + Int(data[1])
        #expect(data[completionOffset1] == 1)
    }

    @Test("BLEDataEncoder encodeTaskList filters non-today tasks")
    func encodeTaskListFiltersNonToday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tasks = [
            TaskItem(title: "Yesterday task", dueDate: yesterday),
        ]
        let data = BLEDataEncoder.encodeTaskList(tasks)
        #expect(data[0] == 0)
    }

    @Test("BLEDataEncoder encodeWeather handles negative temperature")
    func encodeWeatherSignedTemperature() {
        let weather = Weather(temperature: -10, condition: .snowy)
        let data = BLEDataEncoder.encodeWeather(weather)
        let temp = Int8(bitPattern: data[0])
        #expect(temp == -10)
    }

    @Test("BLEDataEncoder encodeWeather handles positive temperature")
    func encodeWeatherPositiveTemperature() {
        let weather = Weather(temperature: 30, condition: .sunny)
        let data = BLEDataEncoder.encodeWeather(weather)
        let temp = Int8(bitPattern: data[0])
        #expect(temp == 30)
    }

    @Test("BLEDataEncoder encodeCurrentTime uses year-2000 offset")
    func encodeTimeYearOffset() {
        let data = BLEDataEncoder.encodeCurrentTime()
        #expect(data.count == 6)
        let year = Int(data[0]) + 2000
        let currentYear = Calendar.current.component(.year, from: Date())
        #expect(year == currentYear)
    }

    @Test("BLEDataEncoder encodeDeviceMode encodes interactive as 0x00")
    func encodeDeviceModeInteractive() {
        let data = BLEDataEncoder.encodeDeviceMode(.interactive)
        #expect(data.count == 1)
        #expect(data[0] == 0x00)
    }

    @Test("BLEDataEncoder encodeDeviceMode encodes focus as 0x01")
    func encodeDeviceModeFocus() {
        let data = BLEDataEncoder.encodeDeviceMode(.focus)
        #expect(data.count == 1)
        #expect(data[0] == 0x01)
    }

    @Test("BLEDataEncoder encodeEventLogRequest encodes timestamp big-endian")
    func encodeEventLogRequestFormat() {
        let timestamp: UInt32 = 1_700_000_000
        let data = BLEDataEncoder.encodeEventLogRequest(since: timestamp)
        #expect(data.count == 4)
        let decoded = UInt32(data[0]) << 24 | UInt32(data[1]) << 16
            | UInt32(data[2]) << 8 | UInt32(data[3])
        #expect(decoded == timestamp)
    }

    @Test("BLEDataEncoder encodeDayPack header format")
    func encodeDayPackHeader() {
        let settlement = SettlementData(
            tasksCompleted: 2, tasksTotal: 5, pointsEarned: 100,
            streakDays: 3, petMood: "happy",
            summaryMessage: "Good day", encouragementMessage: "Keep going"
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let pack = DayPack(
            date: date,
            deviceMode: .interactive,
            focusChallengeEnabled: true,
            morningGreeting: "Good morning",
            dailySummary: "3 tasks today",
            firstItem: "Write tests",
            companionPhrase: "You can do it",
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack)

        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(data[0] == UInt8((components.year ?? 2024) - 2000))
        #expect(data[1] == UInt8(components.month ?? 1))
        #expect(data[2] == UInt8(components.day ?? 1))
        #expect(data[3] == 0x00)
        #expect(data[4] == 0x01)
    }

    @Test("BLEDataEncoder encodeTaskInPage format")
    func encodeTaskInPageFormat() {
        let taskInPage = TaskInPageData(
            taskId: "task-1",
            taskTitle: "Write BLE tests",
            taskDescription: "Add comprehensive tests",
            estimatedDuration: "30m",
            encouragement: "Go for it!",
            focusChallengeActive: true
        )
        let data = BLEDataEncoder.encodeTaskInPage(taskInPage)
        let taskIdData = "task-1".data(using: .utf8)!
        #expect(data[0] == UInt8(taskIdData.count))
        let taskIdBytes = data.subdata(in: 1..<(1 + Int(data[0])))
        #expect(String(data: taskIdBytes, encoding: .utf8) == "task-1")
        #expect(data[data.count - 1] == 0x01)
    }

    @Test("String truncation at max length in BLE encoding")
    func stringTruncationAtMaxLength() {
        var data = Data()
        let longString = String(repeating: "A", count: 80)
        data.appendString(longString, maxLength: 50)
        #expect(data[0] == 50)
        #expect(data.count == 51)
    }

    @Test("String encoding with empty string")
    func stringEncodingEmpty() {
        var data = Data()
        data.appendString("", maxLength: 50)
        #expect(data[0] == 0)
        #expect(data.count == 1)
    }

    // MARK: - EventLog BLE Payload Parsing Tests (Original)

    @Test("EventLog task event BLE payload parsing")
    func eventLogTaskPayloadParsing() throws {
        let taskIdString = "task-abc"
        let taskIdData = Data(taskIdString.utf8)
        let timestamp: UInt32 = 1_700_000_100

        var payload = Data()
        payload.append(UInt8(taskIdData.count))
        payload.append(taskIdData)
        payload.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Array($0) })

        let log = EventLog.fromBLEPayload(type: EventLogType.completeTask.rawByte, payload: payload)
        #expect(log?.eventType == .completeTask)
        #expect(log?.taskId == taskIdString)
        #expect(Int(log?.timestamp.timeIntervalSince1970 ?? 0) == Int(timestamp))
    }

    @Test("EventLog no-payload event parsing")
    func eventLogNoPayloadParsing() throws {
        let log = EventLog.fromBLEPayload(type: EventLogType.requestRefresh.rawByte, payload: Data())
        #expect(log?.eventType == .requestRefresh)
    }

    @Test("EventLog low battery parsing")
    func eventLogLowBatteryParsing() throws {
        let payload = Data([42])
        let log = EventLog.fromBLEPayload(type: EventLogType.lowBattery.rawByte, payload: payload)
        #expect(log?.eventType == .lowBattery)
        #expect(log?.batteryLevel == 42)
        #expect(log?.value == 42)
    }

    @Test("EventLog id-only event parsing")
    func eventLogIdOnlyParsing() throws {
        let idString = "event-xyz"
        let idData = Data(idString.utf8)

        var payload = Data()
        payload.append(UInt8(idData.count))
        payload.append(idData)

        let log = EventLog.fromBLEPayload(type: EventLogType.selectedTaskChanged.rawByte, payload: payload)
        #expect(log?.eventType == .selectedTaskChanged)
        #expect(log?.taskId == idString)
    }

    // MARK: - EventLog fromBLEPayload Extended Tests

    @Test("fromBLEPayload enterTaskIn with taskId and timestamp")
    func fromBLEPayloadEnterTaskIn() {
        let taskId = "test-task-123"
        let taskIdData = taskId.data(using: .utf8)!
        var payload = Data()
        payload.append(UInt8(taskIdData.count))
        payload.append(taskIdData)
        let timestamp: UInt32 = 1_700_000_000
        payload.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Array($0) })

        let event = EventLog.fromBLEPayload(type: 0x10, payload: payload)
        #expect(event != nil)
        #expect(event?.eventType == .enterTaskIn)
        #expect(event?.taskId == "test-task-123")
        #expect(Int(event?.timestamp.timeIntervalSince1970 ?? 0) == Int(timestamp))
    }

    @Test("fromBLEPayload lowBattery with level")
    func fromBLEPayloadLowBattery() {
        let payload = Data([42])
        let event = EventLog.fromBLEPayload(type: 0x40, payload: payload)
        #expect(event != nil)
        #expect(event?.eventType == .lowBattery)
        #expect(event?.batteryLevel == 42)
    }

    @Test("fromBLEPayload lowBattery with empty payload defaults to 0")
    func fromBLEPayloadLowBatteryEmpty() {
        let event = EventLog.fromBLEPayload(type: 0x40, payload: Data())
        #expect(event != nil)
        #expect(event?.eventType == .lowBattery)
        #expect(event?.value == 0)
    }

    @Test("fromBLEPayload requestRefresh with empty payload")
    func fromBLEPayloadRequestRefresh() {
        let event = EventLog.fromBLEPayload(type: 0x20, payload: Data())
        #expect(event != nil)
        #expect(event?.eventType == .requestRefresh)
    }

    @Test("fromBLEPayload invalid type returns nil")
    func fromBLEPayloadInvalidType() {
        let event = EventLog.fromBLEPayload(type: 0xFF, payload: Data())
        #expect(event == nil)
    }

    @Test("fromBLEPayload selectedTaskChanged with item ID")
    func fromBLEPayloadSelectedTaskChanged() {
        let itemId = "item-456"
        let itemIdData = itemId.data(using: .utf8)!
        var payload = Data()
        payload.append(UInt8(itemIdData.count))
        payload.append(itemIdData)

        let event = EventLog.fromBLEPayload(type: 0x13, payload: payload)
        #expect(event != nil)
        #expect(event?.eventType == .selectedTaskChanged)
        #expect(event?.taskId == "item-456")
    }

    @Test("fromBLEPayload skipTask with taskId")
    func fromBLEPayloadSkipTask() {
        let taskId = "skip-me"
        let taskIdData = taskId.data(using: .utf8)!
        var payload = Data()
        payload.append(UInt8(taskIdData.count))
        payload.append(taskIdData)
        let timestamp: UInt32 = 1_700_001_000
        payload.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Array($0) })

        let event = EventLog.fromBLEPayload(type: 0x12, payload: payload)
        #expect(event != nil)
        #expect(event?.eventType == .skipTask)
        #expect(event?.taskId == "skip-me")
    }

    @Test("fromBLEPayload deviceWake")
    func fromBLEPayloadDeviceWake() {
        let event = EventLog.fromBLEPayload(type: 0x30, payload: Data())
        #expect(event != nil)
        #expect(event?.eventType == .deviceWake)
    }

    @Test("fromBLEPayload deviceSleep")
    func fromBLEPayloadDeviceSleep() {
        let event = EventLog.fromBLEPayload(type: 0x31, payload: Data())
        #expect(event != nil)
        #expect(event?.eventType == .deviceSleep)
    }

    @Test("fromBLEPayload wheelSelect with item ID")
    func fromBLEPayloadWheelSelect() {
        let itemId = "selected-item"
        let itemIdData = itemId.data(using: .utf8)!
        var payload = Data()
        payload.append(UInt8(itemIdData.count))
        payload.append(itemIdData)

        let event = EventLog.fromBLEPayload(type: 0x14, payload: payload)
        #expect(event != nil)
        #expect(event?.eventType == .wheelSelect)
        #expect(event?.taskId == "selected-item")
    }

    @Test("fromBLEPayload viewEventDetail with event ID")
    func fromBLEPayloadViewEventDetail() {
        let eventId = "evt-789"
        let eventIdData = eventId.data(using: .utf8)!
        var payload = Data()
        payload.append(UInt8(eventIdData.count))
        payload.append(eventIdData)

        let event = EventLog.fromBLEPayload(type: 0x15, payload: payload)
        #expect(event != nil)
        #expect(event?.eventType == .viewEventDetail)
        #expect(event?.taskId == "evt-789")
    }

    @Test("fromBLEPayload encoder button events")
    func fromBLEPayloadEncoderEvents() {
        let up = EventLog.fromBLEPayload(type: 0x01, payload: Data())
        #expect(up?.eventType == .encoderRotateUp)

        let down = EventLog.fromBLEPayload(type: 0x02, payload: Data())
        #expect(down?.eventType == .encoderRotateDown)

        let shortPress = EventLog.fromBLEPayload(type: 0x03, payload: Data())
        #expect(shortPress?.eventType == .encoderShortPress)

        let longPress = EventLog.fromBLEPayload(type: 0x04, payload: Data())
        #expect(longPress?.eventType == .encoderLongPress)
    }

    @Test("fromBLEPayload power button events")
    func fromBLEPayloadPowerEvents() {
        let shortPress = EventLog.fromBLEPayload(type: 0x05, payload: Data())
        #expect(shortPress?.eventType == .powerShortPress)

        let longPress = EventLog.fromBLEPayload(type: 0x06, payload: Data())
        #expect(longPress?.eventType == .powerLongPress)
    }

    @Test("fromBLEPayload task event rejects empty payload")
    func fromBLEPayloadTaskEventEmptyPayload() {
        let event = EventLog.fromBLEPayload(type: 0x10, payload: Data())
        #expect(event == nil)
    }

    @Test("fromBLEPayload task event rejects truncated taskId")
    func fromBLEPayloadTaskEventTruncatedId() {
        let payload = Data([10, 0x41, 0x42, 0x43])
        let event = EventLog.fromBLEPayload(type: 0x11, payload: payload)
        #expect(event == nil)
    }

    // MARK: - EventLogType rawByte Round-Trip Tests

    @Test("EventLogType rawByte round-trip for all types")
    func eventLogTypeRawByteRoundTrip() {
        let allTypes: [EventLogType] = [
            .encoderRotateUp, .encoderRotateDown, .encoderShortPress, .encoderLongPress,
            .powerShortPress, .powerLongPress,
            .enterTaskIn, .completeTask, .skipTask, .selectedTaskChanged, .wheelSelect, .viewEventDetail,
            .requestRefresh, .deviceWake, .deviceSleep, .lowBattery,
        ]
        for eventType in allTypes {
            let rawByte = eventType.rawByte
            let restored = EventLogType(rawByte: rawByte)
            #expect(restored == eventType, "Round-trip failed for \(eventType)")
        }
    }

    @Test("EventLogType legacy raw bytes map correctly")
    func eventLogTypeLegacyRawBytes() {
        #expect(EventLogType(rawByte: 0x07) == .deviceWake)
        #expect(EventLogType(rawByte: 0x08) == .deviceSleep)
        #expect(EventLogType(rawByte: 0x09) == .lowBattery)
    }

    // MARK: - EInkColor Tests

    @Test("EInkColor raw values match Spectra 6 index table")
    func einkColorRawValues() {
        #expect(EInkColor.black.rawValue == 0x0)
        #expect(EInkColor.white.rawValue == 0x1)
        #expect(EInkColor.yellow.rawValue == 0x2)
        #expect(EInkColor.red.rawValue == 0x3)
        #expect(EInkColor.blue.rawValue == 0x5)
        #expect(EInkColor.green.rawValue == 0x6)
    }

    @Test("EInkColor has exactly 6 cases")
    func einkColorCaseCount() {
        #expect(EInkColor.allCases.count == 6)
    }

    @Test("EInkColor packPixelPair packs two pixels into one byte")
    func einkColorPackPixelPair() {
        let byte = EInkColor.packPixelPair(even: .black, odd: .white)
        #expect(byte == 0x01)

        let byte2 = EInkColor.packPixelPair(even: .red, odd: .blue)
        #expect(byte2 == 0x35)
    }

    @Test("EInkColor unpackPixelPair round-trips correctly")
    func einkColorUnpackPixelPair() {
        let byte = EInkColor.packPixelPair(even: .yellow, odd: .green)
        let result = EInkColor.unpackPixelPair(byte)
        #expect(result?.even == .yellow)
        #expect(result?.odd == .green)
    }

    @Test("EInkColor unpackPixelPair returns nil for reserved index")
    func einkColorUnpackReservedIndex() {
        let byte: UInt8 = 0x40 // high nibble = 0x4 (reserved)
        #expect(EInkColor.unpackPixelPair(byte) == nil)
    }

    // MARK: - ScreenConfig Tests

    @Test("ScreenSize fourInch dimensions")
    func screenSizeFourInch() {
        let screen = ScreenSize.fourInch
        #expect(screen.width == 400)
        #expect(screen.height == 600)
        #expect(screen.pixelCount == 240_000)
        #expect(screen.frameBufferSize == 120_000)
        #expect(screen.maxTasks == 3)
    }

    @Test("ScreenSize sevenInch dimensions")
    func screenSizeSevenInch() {
        let screen = ScreenSize.sevenInch
        #expect(screen.width == 800)
        #expect(screen.height == 480)
        #expect(screen.pixelCount == 384_000)
        #expect(screen.frameBufferSize == 192_000)
        #expect(screen.maxTasks == 5)
    }

    // MARK: - BLEDataEncoder Pixel Data Tests

    @Test("BLEDataEncoder encodePixelData packs 4bpp correctly")
    func encodePixelDataPacking() {
        let pixels: [EInkColor] = [.black, .white, .red, .blue]
        let data = BLEDataEncoder.encodePixelData(pixels, width: 2)
        #expect(data.count == 2)
        #expect(data[0] == 0x01) // black(0) | white(1)
        #expect(data[1] == 0x35) // red(3) | blue(5)
    }

    @Test("BLEDataEncoder encodePixelData pads odd pixel count with white")
    func encodePixelDataOddCount() {
        let pixels: [EInkColor] = [.green, .yellow, .red]
        let data = BLEDataEncoder.encodePixelData(pixels, width: 3)
        #expect(data.count == 2)
        #expect(data[0] == 0x62) // green(6) | yellow(2)
        #expect(data[1] == 0x31) // red(3) | white(1) padding
    }

    @Test("BLEDataEncoder encodeScreenConfig format")
    func encodeScreenConfigFormat() {
        let data = BLEDataEncoder.encodeScreenConfig(.fourInch)
        #expect(data.count == 5)
        // width 400 = 0x0190 big-endian
        #expect(data[0] == 0x01)
        #expect(data[1] == 0x90)
        // height 600 = 0x0258 big-endian
        #expect(data[2] == 0x02)
        #expect(data[3] == 0x58)
        // maxTasks = 3
        #expect(data[4] == 3)
    }

    @Test("BLEDataEncoder encodeScreenConfig sevenInch")
    func encodeScreenConfigSevenInch() {
        let data = BLEDataEncoder.encodeScreenConfig(.sevenInch)
        #expect(data.count == 5)
        // width 800 = 0x0320 big-endian
        #expect(data[0] == 0x03)
        #expect(data[1] == 0x20)
        // height 480 = 0x01E0 big-endian
        #expect(data[2] == 0x01)
        #expect(data[3] == 0xE0)
        // maxTasks = 5
        #expect(data[4] == 5)
    }

    @Test("BLEDataEncoder encodeDayPack with sevenInch allows 5 tasks")
    func encodeDayPackSevenInchTaskLimit() {
        let settlement = SettlementData(
            tasksCompleted: 0, tasksTotal: 5, pointsEarned: 0,
            streakDays: 0, petMood: "happy",
            summaryMessage: "s", encouragementMessage: "e"
        )
        let tasks = (0..<5).map { i in
            TaskSummary(id: "t\(i)", title: "Task \(i)", isCompleted: false, priority: 1)
        }
        let pack = DayPack(
            date: Date(),
            deviceMode: .interactive,
            morningGreeting: "hi",
            dailySummary: "sum",
            firstItem: "first",
            topTasks: tasks,
            companionPhrase: "go",
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack, screenSize: .sevenInch)

        // Find task count byte: after header(5) + morningGreeting + dailySummary + firstItem + scheduleSummary + companionPhrase
        // The task count should be 5
        let headerSize = 5
        let greetingSize = 1 + "hi".utf8.count
        let summarySize = 1 + "sum".utf8.count
        let firstItemSize = 1 + "first".utf8.count
        let scheduleSize = 1 + 0 // empty string
        let phraseSize = 1 + "go".utf8.count
        let taskCountOffset = headerSize + greetingSize + summarySize + firstItemSize + scheduleSize + phraseSize
        #expect(data[taskCountOffset] == 5)
    }
}

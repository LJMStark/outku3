import CryptoKit
import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLE Protocol Simulation Tests", .serialized)
struct BLEProtocolSimulationTests {
    private static let sharedSecret = "kirole-ble-simulation-secret"

    @Test("Virtual hardware parses every App-to-Device business command")
    func virtualHardwareParsesEveryAppToDeviceBusinessCommand() throws {
        var hardware = SimulatedHardware()
        let fixtures = ProtocolFixtures()

        let petPacket = BLESimpleEncoder.encode(
            type: BLEDataType.petStatus.rawValue,
            payload: BLEDataEncoder.encodePetStatus(fixtures.pet, companionCharacter: .joy)
        )
        let petStatus = try hardware.receiveSingleAppPacket(petPacket).parsePetStatus()
        #expect(petStatus.name == "Tiko")
        #expect(petStatus.moodByte == Character("H").asciiValue)
        #expect(petStatus.characterId == "joy")

        let taskPacket = BLESimpleEncoder.encode(
            type: BLEDataType.taskList.rawValue,
            payload: BLEDataEncoder.encodeTaskList(fixtures.tasks)
        )
        let taskList = try hardware.receiveSingleAppPacket(taskPacket).parseTaskList()
        #expect(taskList.tasks.map(\.title) == ["Plan BLE", "Review packet"])
        #expect(taskList.tasks.map(\.isCompleted) == [false, true])

        let schedulePacket = BLESimpleEncoder.encode(
            type: BLEDataType.schedule.rawValue,
            payload: BLEDataEncoder.encodeSchedule(fixtures.events)
        )
        let schedule = try hardware.receiveSingleAppPacket(schedulePacket).parseSchedule()
        #expect(schedule.events.map(\.title) == ["HW Sync"])
        #expect(schedule.events.map(\.startTime) == ["09:30"])

        let weatherPacket = BLESimpleEncoder.encode(
            type: BLEDataType.weather.rawValue,
            payload: BLEDataEncoder.encodeWeather(fixtures.weather)
        )
        let weather = try hardware.receiveSingleAppPacket(weatherPacket).parseWeather()
        #expect(weather.temperature == -3)
        #expect(weather.condition == WeatherCondition.rainy.rawValue)
        #expect(weather.highTemp == 4)
        #expect(weather.lowTemp == -6)

        let timePacket = BLESimpleEncoder.encode(
            type: BLEDataType.time.rawValue,
            payload: BLEDataEncoder.encodeCurrentTime()
        )
        let time = try hardware.receiveSingleAppPacket(timePacket).parseCurrentTime()
        #expect((2024...2100).contains(time.year))
        #expect((1...12).contains(Int(time.month)))
        #expect((1...31).contains(Int(time.day)))
        #expect((0...23).contains(Int(time.hour)))

        let deviceModePacket = BLESimpleEncoder.encode(
            type: BLEDataType.deviceMode.rawValue,
            payload: BLEDataEncoder.encodeDeviceMode(.focus)
        )
        #expect(try hardware.receiveSingleAppPacket(deviceModePacket).parseDeviceMode() == .focus)

        let reminderPacket = BLESimpleEncoder.encode(
            type: BLEDataType.smartReminder.rawValue,
            payload: BLEDataEncoder.encodeSmartReminder(
                text: "Take one quiet breath.",
                urgency: .gentle,
                petMood: .focused
            )
        )
        let reminder = try hardware.receiveSingleAppPacket(reminderPacket).parseSmartReminder()
        #expect(reminder.text == "Take one quiet breath.")
        #expect(reminder.urgency == .gentle)
        #expect(reminder.petMoodByte == Character("F").asciiValue)

        let eventRequestPacket = BLESimpleEncoder.encode(
            type: BLEDataType.eventLogRequest.rawValue,
            payload: BLEDataEncoder.encodeEventLogRequest(since: fixtures.timestamp)
        )
        #expect(try hardware.receiveSingleAppPacket(eventRequestPacket).parseEventLogRequestSince() == fixtures.timestamp)
    }

    @Test("Virtual hardware reassembles and parses chunked DayPack and TaskInPage")
    func virtualHardwareReassemblesChunkedPagePayloads() throws {
        var hardware = SimulatedHardware()
        let fixtures = ProtocolFixtures()

        let dayPackPayload = BLEDataEncoder.encodeDayPack(fixtures.dayPack, screenSize: .fourInch)
        let dayPackPackets = try BLEPacketizer.packetize(
            type: BLEDataType.dayPack.rawValue,
            messageId: 0x5101,
            payload: dayPackPayload,
            maxChunkSize: 24
        )
        let assembledDayPack = try #require(try hardware.receiveAppPacketStream(dayPackPackets))
        let parsedDayPack = try assembledDayPack.parseDayPack()
        #expect(assembledDayPack.type == BLEDataType.dayPack.rawValue)
        #expect(parsedDayPack.date == (year: 2026, month: 5, day: 7))
        #expect(parsedDayPack.deviceMode == .interactive)
        #expect(parsedDayPack.focusChallengeEnabled == true)
        #expect(parsedDayPack.petDialogue == "Small steps count.")
        #expect(parsedDayPack.daySummary == "Two events today. Take a break before noon.")
        #expect(parsedDayPack.firstUp == "09:30 HW Sync")
        #expect(parsedDayPack.events.map(\.title) == ["HW Sync"])
        #expect(parsedDayPack.events.first?.time == "09:30")
        #expect(parsedDayPack.events.first?.description == "Bring the logic analyzer.")
        #expect(parsedDayPack.topTasks.map(\.title) == ["Plan BLE", "Review packet"])
        #expect(parsedDayPack.topTasks.map(\.priority) == [2, 1])
        #expect(parsedDayPack.settlement.tasksCompleted == 1)
        #expect(parsedDayPack.settlement.tasksTotal == 2)
        #expect(parsedDayPack.settlement.pointsEarned == 42)
        #expect(parsedDayPack.settlement.totalFocusMinutes == 35)
        #expect(parsedDayPack.settlement.longestFocusMinutes == 35)
        #expect(parsedDayPack.settlement.interruptionCount == 0)

        let taskInPayload = BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage)
        let taskInPackets = try BLEPacketizer.packetize(
            type: BLEDataType.taskInPage.rawValue,
            messageId: 0x5102,
            payload: taskInPayload,
            maxChunkSize: 18
        )
        let assembledTaskIn = try #require(try hardware.receiveAppPacketStream(taskInPackets))
        let parsedTaskIn = try assembledTaskIn.parseTaskInPage()
        #expect(assembledTaskIn.type == BLEDataType.taskInPage.rawValue)
        #expect(parsedTaskIn.taskId == "task-ble-plan")
        #expect(parsedTaskIn.taskTitle == "Plan BLE")
        #expect(parsedTaskIn.taskDescription == "Check every packet before hardware.")
        #expect(parsedTaskIn.encouragement == "Stay with the next byte.")
        #expect(parsedTaskIn.focusChallengeActive == true)
    }

    @Test("Virtual App parses every Device-to-App event")
    @MainActor
    func virtualAppParsesEveryDeviceToAppEvent() throws {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: nil
        )

        let fixtures = ProtocolFixtures()
        let deviceEvents: [(EventLogType, Data, String?)] = [
            (.encoderRotateUp, Data(), nil),
            (.encoderRotateDown, Data(), nil),
            (.encoderShortPress, Data(), nil),
            (.encoderLongPress, Data(), nil),
            (.powerShortPress, Data(), nil),
            (.powerLongPress, Data(), nil),
            (.enterTaskIn, Self.taskEventPayload(id: fixtures.taskId, timestamp: fixtures.timestamp), fixtures.taskId),
            (.completeTask, Self.taskEventPayload(id: fixtures.taskId, timestamp: fixtures.timestamp), fixtures.taskId),
            (.skipTask, Self.taskEventPayload(id: fixtures.taskId, timestamp: fixtures.timestamp), fixtures.taskId),
            (.selectedTaskChanged, Self.idOnlyPayload(id: fixtures.taskId), fixtures.taskId),
            (.wheelSelect, Self.idOnlyPayload(id: fixtures.taskId), fixtures.taskId),
            (.viewEventDetail, Self.idOnlyPayload(id: fixtures.eventId), fixtures.eventId),
            (.reminderAcknowledged, Self.timestampPayload(fixtures.timestamp), nil),
            (.reminderDismissed, Self.timestampPayload(fixtures.timestamp), nil),
            (.requestRefresh, Data(), nil),
            (.deviceWake, Data(), nil),
            (.deviceSleep, Data(), nil),
            (.lowBattery, Data([17]), nil),
        ]

        for (eventType, payload, expectedId) in deviceEvents {
            let packet = Self.deviceNotifyPacket(type: eventType.rawByte, payload: payload)
            let message = try #require(try BLEService.shared.decodeReceivedMessageForTesting(packet))
            let event = try #require(EventLog.fromBLEPayload(type: message.type, payload: message.payload))

            #expect(event.eventType == eventType)
            if let expectedId {
                #expect(event.taskId == expectedId)
            }
            if [.enterTaskIn, .completeTask, .skipTask, .reminderAcknowledged, .reminderDismissed].contains(eventType) {
                #expect(UInt32(event.timestamp.timeIntervalSince1970) == fixtures.timestamp)
            }
            if eventType == .lowBattery {
                #expect(event.batteryLevel == 17)
            }
        }
    }

    @Test("Virtual App reassembles chunked EventLogBatch before simple decoding")
    @MainActor
    func virtualAppReassemblesChunkedEventLogBatch() throws {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: nil
        )

        let fixtures = ProtocolFixtures()
        var batchPayload = Data()
        batchPayload.append(4)
        batchPayload.append(EventLogType.encoderRotateUp.rawByte)
        batchPayload.append(EventLogType.lowBattery.rawByte)
        batchPayload.append(9)
        batchPayload.append(EventLogType.completeTask.rawByte)
        batchPayload.append(Self.taskEventPayload(id: fixtures.taskId, timestamp: fixtures.timestamp))
        batchPayload.append(EventLogType.reminderDismissed.rawByte)
        batchPayload.append(Self.timestampPayload(fixtures.timestamp + 1))

        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.eventLogBatch.rawValue,
            messageId: 0x5103,
            payload: batchPayload,
            maxChunkSize: 9
        )

        var decodedMessage: BLEReceivedMessage?
        for packet in packets {
            if let message = try BLEService.shared.decodeReceivedMessageForTesting(packet) {
                decodedMessage = message
            }
        }

        let message = try #require(decodedMessage)
        #expect(message.type == BLEDataType.eventLogBatch.rawValue)
        #expect(message.payload == batchPayload)

        let logs = BLEEventHandler.parseEventLogBatchPayload(message.payload)
        #expect(logs.map(\.eventType) == [.encoderRotateUp, .lowBattery, .completeTask, .reminderDismissed])
        #expect(logs[1].batteryLevel == 9)
        #expect(logs[2].taskId == fixtures.taskId)
        #expect(UInt32(logs[2].timestamp.timeIntervalSince1970) == fixtures.timestamp)
    }

    @Test("Malformed length and CRC packets are rejected during simulation")
    func malformedPacketsAreRejected() throws {
        var hardware = SimulatedHardware()
        let payload = Data([0x01, 0x02, 0x03])
        var truncatedSimple = BLESimpleEncoder.encode(type: BLEDataType.weather.rawValue, payload: payload)
        truncatedSimple.removeLast()

        #expect(throws: SimulationError.self) {
            _ = try hardware.receiveSingleAppPacket(truncatedSimple)
        }

        var chunk = try #require(
            BLEPacketizer.packetize(
                type: BLEDataType.dayPack.rawValue,
                messageId: 0x5104,
                payload: Data("chunk-payload".utf8),
                maxChunkSize: 6
            ).first
        )
        chunk[8] ^= 0xFF
        #expect(throws: SimulationError.self) {
            _ = try hardware.receiveAppPacket(chunk)
        }
    }

    @Test("Raw 0xAA packets are rejected as non-standard by the business parser")
    func raw0xAAPacketsRejected() throws {
        // 场景解锁（0x17）、屏保（0x16）均已升级为业务帧，不再有 0xAA 开发命令。
        // 业务帧解析器仍应拒收任何残留的 0xAA 包（过时 App 发来的）。
        let stale0xAA = Data([0xAA, 0x01, 0x01, DisplayScene.forest.commandByte])
        var hardware = SimulatedHardware()
        #expect(throws: SimulationError.self) {
            _ = try hardware.receiveSingleAppPacket(stale0xAA)
        }
    }

    @Test("Secure envelope simulation wraps and opens business payload")
    @MainActor
    func secureEnvelopeSimulationWrapsAndOpensBusinessPayload() throws {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: Self.sharedSecret
        )
        defer {
            AppSecrets.configure(
                supabaseURL: nil,
                supabaseAnonKey: nil,
                openRouterAPIKey: nil,
                bleSharedSecret: nil
            )
        }

        let manager = BLESecurityManager()
        let request = try manager.makeHandshakeRequestPayload()
        let response = try Self.makeHandshakeResponse(for: request)
        try manager.validateHandshakeResponsePayload(response)

        let payload = BLEDataEncoder.encodeDeviceMode(.interactive)
        let securePayload = try manager.securePayload(type: BLEDataType.deviceMode.rawValue, payload: payload)
        let outerPacket = BLESimpleEncoder.encode(type: BLEDataType.secureData.rawValue, payload: securePayload)
        var hardware = SimulatedHardware()
        let outerMessage = try hardware.receiveSingleAppPacket(outerPacket)
        #expect(outerMessage.type == BLEDataType.secureData.rawValue)

        let opened = try manager.openSecurePayload(outerMessage.payload)
        #expect(opened.type == BLEDataType.deviceMode.rawValue)
        #expect(opened.payload == payload)
    }

    @Test("Screen and pixel helper encoders match hardware-facing byte layout")
    func screenAndPixelHelperEncodersMatchByteLayout() throws {
        let screenConfig = BLEDataEncoder.encodeScreenConfig(.fourInch)
        #expect(screenConfig == Data([0x01, 0x90, 0x02, 0x58, 0x03]))

        let pixels: [EInkColor] = [.black, .white, .red, .blue, .green, .yellow]
        let pixelData = BLEDataEncoder.encodePixelData(pixels, width: 3)
        #expect(pixelData == Data([0x01, 0x35, 0x62]))
    }

    private static func deviceNotifyPacket(type: UInt8, payload: Data) -> Data {
        var data = Data([type, UInt8(payload.count)])
        data.append(payload)
        return data
    }

    private static func taskEventPayload(id: String, timestamp: UInt32) -> Data {
        var data = idOnlyPayload(id: id)
        data.append(timestampPayload(timestamp))
        return data
    }

    private static func idOnlyPayload(id: String) -> Data {
        var data = Data()
        data.appendString(id, maxLength: 36)
        return data
    }

    private static func timestampPayload(_ timestamp: UInt32) -> Data {
        var data = Data()
        data.appendBigEndian(timestamp)
        return data
    }

    private static func makeHandshakeResponse(for request: Data) throws -> Data {
        guard request.count >= 9 else {
            throw SimulationError.invalidSecureHandshake
        }

        let clientNonce = request.subdata(in: 1..<9)
        let serverNonce = Data(repeating: 0x51, count: 8)
        let issuedAt = UInt32(Date().timeIntervalSince1970)

        var signedData = Data()
        signedData.append(0x02)
        signedData.append(clientNonce)
        signedData.append(serverNonce)
        signedData.appendBigEndian(issuedAt)

        var response = signedData
        response.append(signature(for: signedData))
        return response
    }

    private static func signature(for data: Data) -> Data {
        let key = SymmetricKey(data: Data(Self.sharedSecret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(code)
    }
}

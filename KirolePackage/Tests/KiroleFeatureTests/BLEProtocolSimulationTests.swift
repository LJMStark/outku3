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

    @Test("Virtual hardware receives only printable ASCII even when App DayPack fields carry LLM/user junk")
    func virtualHardwareReceivesAsciiOnly() throws {
        var hardware = SimulatedHardware()

        // A DayPack whose text fields carry exactly the non-ASCII an LLM / user / calendar produces:
        // curly quotes, em-dash, ellipsis, accent, bullet, currency, non-breaking hyphen, emoji.
        let dirty = DayPack(
            date: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 5, day: 7).date ?? Date(),
            deviceMode: .interactive,
            focusChallengeEnabled: true,
            petDialogue: "You\u{2019}re doing great \u{2014} keep it up! \u{1F31F}",
            daySummary: "A quiet day\u{2026} no events, so it\u{2019}s a good chance to recharge.",
            firstUp: "10:00 Caf\u{00E9} catch\u{2011}up",
            events: [
                EventSummary(time: "09:30",
                             title: "Meet Jos\u{00E9} \u{2022} review",
                             description: "Bring \u{20AC}20 & the \u{201C}notes\u{201D}"),
            ],
            topTasks: [
                TaskSummary(id: "task-ble-plan", title: "Buy groceries \u{1F6D2}", isCompleted: false, priority: 2),
            ],
            settlementData: SettlementData(
                tasksCompleted: 1, tasksTotal: 2, pointsEarned: 42, petMood: "happy",
                summaryMessage: "", encouragementMessage: "",
                totalFocusMinutes: 35, focusSessionCount: 1, longestFocusMinutes: 35,
                interruptionCount: 0, totalEnergyBottles: 1
            )
        )

        // App encodes -> BLE wire (chunked at a realistic MTU) -> hardware reassembles + parses.
        let payload = BLEDataEncoder.encodeDayPack(dirty, screenSize: .fourInch)
        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.dayPack.rawValue, messageId: 0x5150, payload: payload, maxChunkSize: 24
        )
        let assembled = try #require(try hardware.receiveAppPacketStream(packets))
        let hw = try assembled.parseDayPack()

        let fields: [(name: String, appSide: String, wire: String)] = [
            ("petDialogue", dirty.petDialogue, hw.petDialogue),
            ("daySummary",  dirty.daySummary,  hw.daySummary),
            ("firstUp",     dirty.firstUp,     hw.firstUp),
            ("event.title", dirty.events[0].title, hw.events.first?.title ?? ""),
            ("event.desc",  dirty.events[0].description, hw.events.first?.description ?? ""),
            ("task.title",  dirty.topTasks[0].title, hw.topTasks.first?.title ?? ""),
        ]
        print("\n════ Virtual hardware DayPack decode: App field -> on-wire bytes the firmware reads ════")
        for f in fields {
            let bytes = Array(f.wire.utf8)
            let isAscii = bytes.allSatisfy { $0 >= 0x20 && $0 <= 0x7E }
            let hex = bytes.map { String(format: "%02X", Int($0)) }.joined(separator: " ")
            print("• \(f.name): ascii=\(isAscii ? "PASS" : "FAIL")")
            print("    app  : \(f.appSide)")
            print("    wire : \(f.wire)")
            print("    hex  : \(hex)")
            #expect(isAscii, "\(f.name) put a non-ASCII byte on the wire: \(f.wire)")
        }
        print("════ every DayPack text field the virtual hardware received is printable ASCII (0x20-0x7E) ════\n")

        // The hardware sees the readable ASCII transliteration, not tofu.
        #expect(hw.daySummary == "A quiet day... no events, so it's a good chance to recharge.")
        #expect(hw.petDialogue == "You're doing great - keep it up! ")
        #expect(hw.events.first?.description == "Bring 20 & the \"notes\"")
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

    // 旧 4bpp pixel helper 仿真已随量化链删除（v2.5.24 起 0x15 改传 PNG）。

    @Test("Virtual hardware reassembles a chunked CustomAvatarFrame PNG payload")
    func virtualHardwareReassemblesChunkedCustomAvatarFrame() throws {
        // 小合成 PNG：8 字节签名 + 确定性填充，足以验证 0x15 分包→重组→载荷布局全链路。
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let pngData = Data(pngSignature + (0..<300).map { UInt8($0 % 251) })
        let payload = BLEDataEncoder.encodeCustomAvatarFrame(pngData: pngData)

        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.customAvatarFrame.rawValue,
            messageId: 0x0007,
            payload: payload,
            maxChunkSize: 24
        )
        #expect(packets.count > 1) // 0x15 恒走分包（§4.12）

        var hardware = SimulatedHardware()
        let message = try hardware.receiveAppPacketStream(packets)
        #expect(message?.type == BLEDataType.customAvatarFrame.rawValue)
        #expect(message?.transport == .chunked)
        #expect(message?.payload.first == 0x02) // SubVersion v2 = PNG
        #expect(message.map { Data($0.payload.dropFirst()) } == pngData)
    }

    @Test("Simulated firmware reassembles a 1MiB PNG avatar frame across 2093 chunks")
    func simulatedFirmwareReassemblesMegabytePNGAvatarFrame() throws {
        // 1MiB 上限用例走固件视角镜像重组器（SimulatedFirmwareChunkReassembler）：
        // 生产 BLEPacketAssembler 的 256KiB 帽只管 Device→App 入站、故意不抬。
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        var pngData = Data(capacity: 1_048_576)
        pngData.append(contentsOf: pngSignature)
        pngData.append(Data((0..<(1_048_576 - pngSignature.count)).map { UInt8($0 % 251) }))
        let payload = BLEDataEncoder.encodeCustomAvatarFrame(pngData: pngData)
        #expect(payload.count == 1_048_577)

        // 协商 512B 写长度 - 11B 分包头 = 501B/片 → ceil(1,048,577 / 501) = 2093 片。
        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.customAvatarFrame.rawValue,
            messageId: 0x0100,
            payload: payload,
            maxChunkSize: 501
        )
        #expect(packets.count == 2093)

        var reassembler = SimulatedFirmwareChunkReassembler()
        var assembled: Data?
        for packet in packets {
            if let complete = try reassembler.receive(packet) {
                assembled = complete
            }
        }
        #expect(assembled?.count == payload.count)
        #expect(assembled == payload)
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

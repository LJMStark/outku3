import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLE Protocol Tests")
struct BLEProtocolTests {

    private func readString(from data: Data, cursor: inout Int) -> String? {
        guard cursor < data.count else { return nil }
        let length = Int(data[cursor])
        cursor += 1
        guard cursor + length <= data.count else { return nil }
        let stringData = data.subdata(in: cursor..<(cursor + length))
        cursor += length
        return String(data: stringData, encoding: .utf8)
    }

    private func threeChunkMessage(messageId: UInt16) throws -> [Data] {
        try BLEPacketizer.packetize(
            type: 0x21,
            messageId: messageId,
            payload: Data([UInt8(truncatingIfNeeded: messageId), 0xA5, 0x5A]),
            maxChunkSize: 1
        )
    }

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

    @Test("BLEPacketizer emits 11-byte header with 2-byte Seq/Total and per-chunk CRC16")
    func packetizerChunkHeaderFields() throws {
        let payload = Data((0..<10).map { UInt8($0) })
        let packets = try BLEPacketizer.packetize(
            type: 0x10,
            messageId: 0x1234,
            payload: payload,
            maxChunkSize: 4
        )

        #expect(packets.count == 3)

        let first = packets[0]
        #expect(first[0] == 0x10)
        #expect(first[1] == 0x12)
        #expect(first[2] == 0x34)
        // v2.5.24: Seq/Total 各 2B BE（协议 §3.2）
        #expect(first[3] == 0x00)
        #expect(first[4] == 0x00)
        #expect(first[5] == 0x00)
        #expect(first[6] == 0x03)
        #expect(first[7] == 0x00)
        #expect(first[8] == 0x04)
        let firstPayload = first.subdata(in: BLEPacketizer.headerSize..<first.count)
        let firstCRC = first.bigEndianUInt16(at: 9)
        #expect(firstCRC == CRC16.ccittFalse(firstPayload))

        let third = packets[2]
        #expect(third[3] == 0x00)
        #expect(third[4] == 0x02)
        #expect(third[5] == 0x00)
        #expect(third[6] == 0x03)
        #expect(third[7] == 0x00)
        #expect(third[8] == 0x02)
        let thirdPayload = third.subdata(in: BLEPacketizer.headerSize..<third.count)
        let thirdCRC = third.bigEndianUInt16(at: 9)
        #expect(thirdCRC == CRC16.ccittFalse(thirdPayload))
    }

    @Test("BLEPacketAssembler rejects packet shorter than header")
    func assemblerRejectsTooShort() {
        let assembler = BLEPacketAssembler()
        let shortData = Data([0x01, 0x02, 0x03])
        #expect(assembler.append(packetData: shortData) == nil)
        // 10 字节在旧 9B 头下曾可解析——钉死 v2.5.24 的 11B 新边界。
        let nineByteEraPacket = Data(repeating: 0x01, count: 10)
        #expect(assembler.append(packetData: nineByteEraPacket) == nil)
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

    @Test("BLEPacketAssembler rejects packet with invalid per-chunk CRC")
    func assemblerRejectsInvalidChunkCRC() throws {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        var packet = try #require(
            BLEPacketizer.packetize(
                type: 0x10,
                messageId: 0x0101,
                payload: payload,
                maxChunkSize: 4
            ).first
        )
        packet[10] ^= 0xFF // corrupt CRC low byte (CRC field at offset 9-10 in the 11B header)

        let assembler = BLEPacketAssembler()
        let result = assembler.append(packetData: packet)
        #expect(result == nil)
    }

    @Test("BLEPacketAssembler limits in-flight message count")
    func assemblerLimitsInFlightMessages() throws {
        let assembler = BLEPacketAssembler()
        var packetStreams: [[Data]] = []

        for messageId in 1...9 {
            let packets = try BLEPacketizer.packetize(
                type: 0x21,
                messageId: UInt16(messageId),
                payload: Data(repeating: UInt8(messageId), count: 3),
                maxChunkSize: 2
            )
            let firstChunk = try #require(packets.first)
            _ = assembler.append(packetData: firstChunk)
            packetStreams.append(packets)
        }

        var assembledCount = 0
        for packets in packetStreams {
            for packet in packets.dropFirst() {
                if assembler.append(packetData: packet) != nil {
                    assembledCount += 1
                }
            }
        }

        #expect(assembledCount == 8)
    }

    @Test("Eight unexpired incomplete messages still block a ninth message")
    func assemblerKeepsUnexpiredInFlightLimit() throws {
        let assembler = BLEPacketAssembler()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for messageId in 1...8 {
            let packets = try threeChunkMessage(messageId: UInt16(messageId))
            _ = assembler.append(packetData: try #require(packets.first), now: now)
        }

        let ninthPackets = try threeChunkMessage(messageId: 9)
        var result: BLEReceivedMessage?
        for packet in ninthPackets {
            result = assembler.append(packetData: packet, now: now) ?? result
        }

        #expect(result == nil)
    }

    @Test("Expired incomplete messages release slots without accepting late tail chunks")
    func assemblerEvictsExpiredMessagesBeforeNinthMessage() throws {
        let assembler = BLEPacketAssembler()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredAt = startedAt.addingTimeInterval(10 * 60)
        var stalePacketStreams: [[Data]] = []

        for messageId in 1...8 {
            let packets = try threeChunkMessage(messageId: UInt16(messageId))
            _ = assembler.append(packetData: try #require(packets.first), now: startedAt)
            stalePacketStreams.append(packets)
        }

        // Each old stream still has two tail chunks. Sending one tail per expired ID would
        // refill all eight slots unless expiry leaves a bounded tombstone for late packets.
        for packets in stalePacketStreams {
            _ = assembler.append(packetData: packets[1], now: expiredAt)
        }

        let ninthPackets = try threeChunkMessage(messageId: 9)
        var result: BLEReceivedMessage?
        for packet in ninthPackets {
            result = assembler.append(packetData: packet, now: expiredAt) ?? result
        }

        #expect(result?.type == 0x21)
        #expect(result?.payload == Data([0x09, 0xA5, 0x5A]))
    }

    @Test("BLEPacketizer accepts exactly 65535 chunks (v2.5.24 ceiling)")
    func packetizerAcceptsExactly65535Chunks() throws {
        let packets = try BLEPacketizer.packetize(
            type: 0x15,
            messageId: 1,
            payload: Data(count: 65535),
            maxChunkSize: 1
        )
        #expect(packets.count == 65535)
        let last = try #require(packets.last)
        // 末片 Seq=65534(0xFFFE)、Total=65535(0xFFFF)，各 2B BE
        #expect(last[3] == 0xFF)
        #expect(last[4] == 0xFE)
        #expect(last[5] == 0xFF)
        #expect(last[6] == 0xFF)
    }

    @Test("BLEPacketizer rejects 65536 chunks")
    func packetizerRejects65536Chunks() {
        #expect(throws: BLEPacketError.self) {
            _ = try BLEPacketizer.packetize(
                type: 0x15,
                messageId: 1,
                payload: Data(count: 65536),
                maxChunkSize: 1
            )
        }
    }

    @Test("Packetize/assemble round-trips a payload beyond the old 255-chunk limit")
    func packetizeAssembleLargePayloadRoundTrip() throws {
        // ~200KB @ 509B/片 → 393 片：超旧 255 上限、低于 Assembler 的 256KiB 入站帽。
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        let packets = try BLEPacketizer.packetize(
            type: 0x21,
            messageId: 0x0042,
            payload: payload,
            maxChunkSize: 509
        )
        #expect(packets.count == 393)

        let assembler = BLEPacketAssembler()
        var result: BLEReceivedMessage?
        for packet in packets {
            if let message = assembler.append(packetData: packet) {
                result = message
            }
        }
        #expect(result?.type == 0x21)
        #expect(result?.payload == payload)
    }

    @Test("Assembler drops an inbound message exceeding the 256KiB cap")
    func assemblerDropsOverCapMessage() throws {
        // 65535 片上限放开后，256KiB 入站帽成了 Device→App 方向唯一的内存防线——
        // 钉死它真的会丢弃超限消息（帽中途触发并整条驱逐）。
        let payload = Data(count: 256 * 1024 + 1)
        let packets = try BLEPacketizer.packetize(
            type: 0x21,
            messageId: 0x0099,
            payload: payload,
            maxChunkSize: 509
        )
        let assembler = BLEPacketAssembler()
        var assembled: BLEReceivedMessage?
        for packet in packets {
            if let message = assembler.append(packetData: packet) {
                assembled = message
            }
        }
        #expect(assembled == nil)
    }

    @Test("Over-cap message tail chunks do not consume an in-flight slot")
    func overCapMessageTailChunksDoNotConsumeSlot() throws {
        let droppedMessageId: UInt16 = 0x0099
        let oversizedPackets = try BLEPacketizer.packetize(
            type: 0x21,
            messageId: droppedMessageId,
            payload: Data(count: 256 * 1024 + 1024),
            maxChunkSize: 509
        )
        let assembler = BLEPacketAssembler()

        for packet in oversizedPackets {
            _ = assembler.append(packetData: packet)
        }

        var packetStreams: [[Data]] = []
        for messageId in 1...8 {
            let packets = try BLEPacketizer.packetize(
                type: 0x21,
                messageId: UInt16(messageId),
                payload: Data(repeating: UInt8(messageId), count: 3),
                maxChunkSize: 2
            )
            let firstChunk = try #require(packets.first)
            _ = assembler.append(packetData: firstChunk)
            packetStreams.append(packets)
        }

        var assembledCount = 0
        for packets in packetStreams {
            for packet in packets.dropFirst() {
                if assembler.append(packetData: packet) != nil {
                    assembledCount += 1
                }
            }
        }

        #expect(assembledCount == 8)
    }

    @Test("Over-cap message accepts a same-ID retransmission starting at sequence zero")
    func overCapMessageAcceptsSameIdRetransmission() throws {
        let messageId: UInt16 = 0x0099
        let oversizedPackets = try BLEPacketizer.packetize(
            type: 0x21,
            messageId: messageId,
            payload: Data(count: 256 * 1024 + 1024),
            maxChunkSize: 509
        )
        let assembler = BLEPacketAssembler()

        for packet in oversizedPackets {
            _ = assembler.append(packetData: packet)
        }

        let retransmittedPayload = Data("retry".utf8)
        let retransmittedPackets = try BLEPacketizer.packetize(
            type: 0x21,
            messageId: messageId,
            payload: retransmittedPayload,
            maxChunkSize: 2
        )
        var result: BLEReceivedMessage?
        for packet in retransmittedPackets {
            if let message = assembler.append(packetData: packet) {
                result = message
            }
        }

        #expect(result?.type == 0x21)
        #expect(result?.payload == retransmittedPayload)
    }

    @Test("Sequence zero restarts an in-flight message instead of reusing old tail chunks")
    func sequenceZeroRestartsInFlightMessage() throws {
        let messageID: UInt16 = 0x0044
        let oldPackets = try BLEPacketizer.packetize(
            type: 0x21,
            messageId: messageID,
            payload: Data("old-tail".utf8),
            maxChunkSize: 3
        )
        let newPayload = Data("new-data".utf8)
        let newPackets = try BLEPacketizer.packetize(
            type: 0x21,
            messageId: messageID,
            payload: newPayload,
            maxChunkSize: 3
        )
        let assembler = BLEPacketAssembler()

        _ = assembler.append(packetData: oldPackets[2])
        _ = assembler.append(packetData: newPackets[0])
        _ = assembler.append(packetData: newPackets[1])
        #expect(assembler.append(packetData: newPackets[2])?.payload == newPayload)
    }

    @Test("Assembler rejects zero-length chunks")
    func assemblerRejectsZeroLengthChunk() {
        // packetize 永不产生空片（空 payload 直接抛错）——零长度片只可能是坏包或
        // 恶意填充 65535 个空片撑爆重组字典（256KiB 帽数不到字典项），必须整片拒收。
        var packet = Data()
        packet.append(0x21)                       // type
        packet.appendBigEndian(UInt16(0x0007))    // messageId
        packet.appendBigEndian(UInt16(0))         // seq
        packet.appendBigEndian(UInt16(2))         // total = 2（非末片也为空）
        packet.appendBigEndian(UInt16(0))         // payloadLen = 0
        packet.appendBigEndian(CRC16.ccittFalse(Data())) // 空数据的合法 CRC
        #expect(packet.count == BLEPacketizer.headerSize)

        let assembler = BLEPacketAssembler()
        #expect(assembler.append(packetData: packet) == nil)
        #expect(assembler.isPotentialChunk(packetData: packet) == false)
    }

    @Test("BLE inbound decode prefers chunked packets over simple packets")
    @MainActor
    func inboundDecodePrefersChunkedPackets() throws {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: nil
        )

        let payload = Data("chunked-event-log-batch".utf8)
        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.eventLogBatch.rawValue,
            messageId: 0x0001,
            payload: payload,
            maxChunkSize: 8
        )

        let service = BLEService.shared
        var decoded: BLEReceivedMessage?
        for packet in packets {
            if let message = try service.decodeReceivedMessageForTesting(packet) {
                decoded = message
            }
        }

        #expect(decoded?.type == BLEDataType.eventLogBatch.rawValue)
        #expect(decoded?.payload == payload)
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
            petMood: "happy",
            summaryMessage: "summary",
            encouragementMessage: "encourage"
        )

        let packA = DayPack(
            date: baseDate,
            weather: WeatherInfo(temperature: 20, highTemp: 25, lowTemp: 15, condition: "Clear", iconName: "Clear"),
            deviceMode: .interactive,
            focusChallengeEnabled: false,
            petDialogue: "phrase",
            events: [EventSummary(time: "09:00", title: "Sync", description: "team")],
            topTasks: [TaskSummary(id: "1", title: "A", isCompleted: false, priority: 1, dueTime: "09:00")],
            settlementData: settlement
        )

        let packB = DayPack(
            date: baseDate,
            weather: WeatherInfo(temperature: 20, highTemp: 25, lowTemp: 15, condition: "Clear", iconName: "Clear"),
            deviceMode: .interactive,
            focusChallengeEnabled: false,
            petDialogue: "phrase-updated",
            events: [EventSummary(time: "09:00", title: "Sync", description: "team")],
            topTasks: [TaskSummary(id: "1", title: "A", isCompleted: false, priority: 1, dueTime: "09:00")],
            settlementData: settlement
        )

        #expect(packA.stableFingerprint() != packB.stableFingerprint())
        #expect(packA.stableFingerprint() == packA.stableFingerprint())
    }

    @Test("DayPack fingerprint frames fields without delimiter collisions")
    func dayPackFingerprintAvoidsDelimiterCollisions() {
        let settlement = SettlementData(
            tasksCompleted: 1,
            tasksTotal: 3,
            pointsEarned: 10,
            petMood: "happy",
            summaryMessage: "summary",
            encouragementMessage: "encourage"
        )
        let commonDate = Date(timeIntervalSince1970: 1_700_000_000)

        let packA = DayPack(
            date: commonDate,
            petDialogue: "a|daySummary=b",
            daySummary: "c",
            settlementData: settlement
        )
        let packB = DayPack(
            date: commonDate,
            petDialogue: "a",
            daySummary: "b|daySummary=c",
            settlementData: settlement
        )

        #expect(packA.stableFingerprint() != packB.stableFingerprint())
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

    @Test("BLESimpleDecoder rejects trailing bytes")
    func simpleDecoderRejectsTrailingBytes() {
        let data = Data([0x10, 0x01, 0xAA, 0xBB])
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
        let length = encoded.bigEndianUInt16(at: 1)
        #expect(length == 4)
        #expect(encoded.subdata(in: 3..<7) == payload)
    }

    // MARK: - BLEDataEncoder Tests

    @Test("BLEDataEncoder encodePetStatus produces correct format")
    func encodePetStatusFormat() {
        let pet = Pet(name: "Tiko", mood: .happy)
        let data = BLEDataEncoder.encodePetStatus(pet, companionCharacter: .joy, customActive: false)

        let nameLen = Int(data[0])
        #expect(nameLen == 4)
        let nameBytes = data.subdata(in: 1..<(1 + nameLen))
        #expect(String(data: nameBytes, encoding: .utf8) == "Tiko")

        let moodOffset = 1 + nameLen
        #expect(data[moodOffset] == Character("H").asciiValue!)

        let characterOffset = moodOffset + 1
        let characterLen = Int(data[characterOffset])
        let characterBytes = data.subdata(in: (characterOffset + 1)..<(characterOffset + 1 + characterLen))
        #expect(String(data: characterBytes, encoding: .utf8) == "joy")

        // v2.5.32: CustomActive 尾字节，且为最后一个字节
        let customActiveOffset = characterOffset + 1 + characterLen
        #expect(data[customActiveOffset] == 0x00)
        #expect(customActiveOffset == data.count - 1)

        let customData = BLEDataEncoder.encodePetStatus(pet, companionCharacter: .joy, customActive: true)
        #expect(customData[customData.count - 1] == 0x01)
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

    @Test("BLEDataEncoder encodeTaskList includes a task manually selected for today")
    func encodeTaskListIncludesManualTodaySelection() {
        let task = TaskItem(
            title: "No due date",
            dueDate: nil,
            todayDisplayDate: Date()
        )

        let data = BLEDataEncoder.encodeTaskList([task])

        #expect(data[0] == 1)
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

    @Test("BLEDataEncoder encodeWeather appends high/low temps (v2.5.9)")
    func encodeWeatherHighLow() {
        let weather = Weather(temperature: 5, highTemp: 12, lowTemp: -3, condition: .cloudy)
        let data = BLEDataEncoder.encodeWeather(weather)
        // Layout: [temp:int8][condition: 1+N][high:int8][low:int8]
        #expect(Int8(bitPattern: data[0]) == 5)
        let condLen = Int(data[1])
        #expect(Int8(bitPattern: data[2 + condLen]) == 12)   // high
        #expect(Int8(bitPattern: data[3 + condLen]) == -3)   // low
        #expect(data.count == 4 + condLen)                   // no trailing bytes
    }

    @Test("BLEDataEncoder encodeSchedule emits StartTime as exactly 5 ASCII bytes (locale-pinned)")
    func encodeScheduleStartTimeIsAscii() {
        // A today event at 09:30 — passes the isDateInToday filter inside encodeSchedule.
        let start = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date())!
        let event = CalendarEvent(title: "Sync", startTime: start, endTime: start.addingTimeInterval(1800))
        let data = BLEDataEncoder.encodeSchedule([event])

        // Layout: [count:1][titleLen:1][title:N][StartTime: fixed 5 bytes "HH:mm" (§4.4)]
        #expect(data[0] == 1)
        let titleLen = Int(data[1])
        let timeBytes = data.subdata(in: (2 + titleLen)..<data.count)
        #expect(timeBytes.count == 5)                                 // fixed 5-byte field, not length-prefixed
        #expect(timeBytes == Data("09:30".utf8))                      // ASCII digits — en_US_POSIX, not user locale
        #expect(timeBytes.allSatisfy { $0 >= 0x20 && $0 <= 0x7E })    // never tofu on the wire
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

    @Test("BLEDataType includes SmartReminder command")
    func bleDataTypeHasSmartReminder() {
        #expect(BLEDataType.smartReminder.rawValue == 0x13)
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

    @Test("BLEDataEncoder encodeDayPack format excludes legacy microAction fields")
    func encodeDayPackFormatExcludesMicroActionFields() {
        let settlement = SettlementData(
            tasksCompleted: 2, tasksTotal: 5, pointsEarned: 100,
            petMood: "happy",
            summaryMessage: "Good day", encouragementMessage: "Keep going"
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let pack = DayPack(
            date: date,
            deviceMode: .interactive,
            focusChallengeEnabled: true,
            petDialogue: "Good morning",
            events: [
                EventSummary(time: "09:00", title: "Standup", description: "Sync")
            ],
            topTasks: [
                TaskSummary(id: "task-1", title: "Review docs", isCompleted: false, priority: 2)
            ],
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack)

        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(data[0] == UInt8((components.year ?? 2024) - 2000))
        #expect(data[1] == UInt8(components.month ?? 1))
        #expect(data[2] == UInt8(components.day ?? 1))
        #expect(data[3] == 0x00)
        #expect(data[4] == 0x01)

        var cursor = 5
        #expect(readString(from: data, cursor: &cursor) == "Good morning")   // PetDialogue
        #expect(data[cursor] == 1)                                           // EventCount
        cursor += 1
        #expect(readString(from: data, cursor: &cursor) == "09:00")          // Event.time
        #expect(readString(from: data, cursor: &cursor) == "Standup")        // Event.title
        #expect(readString(from: data, cursor: &cursor) == "Sync")           // Event.description
        #expect(data[cursor] == EventCategory.unknown.rawValue)              // Event.category (v2.5.27)
        cursor += 1
        #expect(readString(from: data, cursor: &cursor) == "")               // Event.endTime (v2.5.30)
        #expect(data[cursor] == 1)                                           // TaskCount
        cursor += 1
        #expect(readString(from: data, cursor: &cursor) == "task-1")
        #expect(readString(from: data, cursor: &cursor) == "Review docs")
        #expect(data[cursor] == 0x00)
        cursor += 1
        #expect(data[cursor] == 0x02)
    }

    @Test("CJK-only event and task titles use nonempty hardware fallbacks")
    func cjkOnlyDayPackTitlesUseFallbacks() {
        let pack = DayPack(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            petDialogue: "",
            events: [
                EventSummary(time: "", endTime: "", title: "大暑。", description: "")
            ],
            topTasks: [
                TaskSummary(id: "task-cjk", title: "写报告！", isCompleted: false, priority: 1)
            ],
            settlementData: SettlementData(
                tasksCompleted: 0,
                tasksTotal: 2,
                pointsEarned: 0,
                petMood: "happy",
                summaryMessage: "",
                encouragementMessage: ""
            )
        )
        let data = BLEDataEncoder.encodeDayPack(pack)

        var cursor = 5
        #expect(readString(from: data, cursor: &cursor) == "")
        #expect(data[cursor] == 1)
        cursor += 1
        #expect(readString(from: data, cursor: &cursor) == "")
        #expect(readString(from: data, cursor: &cursor) == "Calendar Event")
        #expect(readString(from: data, cursor: &cursor) == "")
        #expect(data[cursor] == EventCategory.unknown.rawValue)
        cursor += 1
        #expect(readString(from: data, cursor: &cursor) == "")
        #expect(data[cursor] == 1)
        cursor += 1
        #expect(readString(from: data, cursor: &cursor) == "task-cjk")
        #expect(readString(from: data, cursor: &cursor) == "Task")
    }

    @Test("CJK-only FirstUp title keeps its time and uses a hardware fallback")
    func cjkOnlyFirstUpTitleUsesFallback() {
        let pack = DayPack(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            petDialogue: "",
            firstUp: "09:30 大暑。",
            settlementData: SettlementData(
                tasksCompleted: 0,
                tasksTotal: 0,
                pointsEarned: 0,
                petMood: "happy",
                summaryMessage: "",
                encouragementMessage: ""
            )
        )
        let data = BLEDataEncoder.encodeDayPack(pack)

        var cursor = 5
        _ = readString(from: data, cursor: &cursor)
        cursor += 1
        cursor += 1
        cursor += 10
        _ = readString(from: data, cursor: &cursor)
        #expect(readString(from: data, cursor: &cursor) == "09:30 Next item")
    }

    @Test("CJK-only task titles use fallback in task detail and focus frames")
    func cjkOnlyDynamicTaskTitlesUseFallbacks() {
        let taskPage = BLEDataEncoder.encodeTaskInPage(
            TaskInPageData(
                taskId: "task-cjk",
                taskTitle: "写报告",
                taskDescription: nil,
                encouragement: "",
                focusChallengeActive: false
            )
        )
        var taskCursor = 0
        #expect(readString(from: taskPage, cursor: &taskCursor) == "task-cjk")
        #expect(readString(from: taskPage, cursor: &taskCursor) == "Task")

        let focus = BLEDataEncoder.encodeFocusStatus(
            phase: .warmup,
            energyBottles: 0,
            elapsedMinutes: 1,
            taskTitle: "写报告",
            segmentMinutes: 1
        )
        var focusCursor = 4
        #expect(readString(from: focus, cursor: &focusCursor) == "Task")

        let idle = BLEDataEncoder.encodeFocusStatus(
            phase: .idle,
            energyBottles: 0,
            elapsedMinutes: 0,
            taskTitle: nil,
            segmentMinutes: 0
        )
        var idleCursor = 4
        #expect(readString(from: idle, cursor: &idleCursor) == "")
    }

    @Test("BLEDataEncoder encodeDayPack appends DaySummary at the tail (v2.5.7)")
    func encodeDayPackAppendsDaySummaryTail() {
        let settlement = SettlementData(
            tasksCompleted: 0, tasksTotal: 0, pointsEarned: 0,
            petMood: "happy", summaryMessage: "", encouragementMessage: ""
        )
        let summary = "You have 2 events today. Take a break before noon."
        let pack = DayPack(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            deviceMode: .interactive,
            focusChallengeEnabled: false,
            petDialogue: "Good morning",
            daySummary: summary,
            firstUp: "09:30 Standup",
            settlementReview: "You completed 2 of 3 items today.",
            settlementQuote: "A full sweep today. Great work, truly.",
            events: [],
            topTasks: [],
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack)

        var cursor = 5
        #expect(readString(from: data, cursor: &cursor) == "Good morning")  // PetDialogue
        #expect(data[cursor] == 0)                                          // EventCount = 0
        cursor += 1
        #expect(data[cursor] == 0)                                          // TaskCount = 0
        cursor += 1
        cursor += 10                                                        // SettlementData: fixed 10 bytes
        #expect(readString(from: data, cursor: &cursor) == summary)         // DaySummary
        #expect(readString(from: data, cursor: &cursor) == "09:30 Standup") // FirstUp
        // v2.5.30/v2.5.31 settlement page tail texts
        #expect(readString(from: data, cursor: &cursor) == "You completed 2 of 3 items today.")
        #expect(readString(from: data, cursor: &cursor) == "A full sweep today. Great work, truly.")
        #expect(cursor == data.count)                                       // SettlementQuote is the final field
    }

    @Test("BLEDataEncoder encodeDayPack truncates settlement texts to their budgets (v2.5.30)")
    func encodeDayPackTruncatesSettlementTexts() {
        let settlement = SettlementData(
            tasksCompleted: 0, tasksTotal: 0, pointsEarned: 0,
            petMood: "happy", summaryMessage: "", encouragementMessage: ""
        )
        let pack = DayPack(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            petDialogue: "x",
            daySummary: "s",
            firstUp: "f",
            settlementReview: String(repeating: "R", count: 200),
            settlementQuote: String(repeating: "Q", count: 200),
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack)
        var cursor = 5
        _ = readString(from: data, cursor: &cursor)    // PetDialogue
        cursor += 1                                    // EventCount = 0
        cursor += 1                                    // TaskCount = 0
        cursor += 10                                   // SettlementData
        _ = readString(from: data, cursor: &cursor)    // DaySummary
        _ = readString(from: data, cursor: &cursor)    // FirstUp
        #expect(data[cursor] == UInt8(DayPackTextBudget.settlementReview))  // 180
        #expect(readString(from: data, cursor: &cursor)?.count == DayPackTextBudget.settlementReview)
        #expect(data[cursor] == UInt8(DayPackTextBudget.settlementQuote))   // 120
        #expect(readString(from: data, cursor: &cursor)?.count == DayPackTextBudget.settlementQuote)
        #expect(cursor == data.count)
    }

    @Test("DayPack fingerprint varies on v2.5.30/31 fields (endTime / settlement texts)")
    func dayPackFingerprintVariesOnSettlementFields() {
        let settlement = SettlementData(
            tasksCompleted: 0, tasksTotal: 0, pointsEarned: 0,
            petMood: "happy", summaryMessage: "", encouragementMessage: ""
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func pack(
            endTime: String = "10:00", review: String = "r", quote: String = "q"
        ) -> DayPack {
            DayPack(
                date: date,
                petDialogue: "p",
                settlementReview: review,
                settlementQuote: quote,
                events: [EventSummary(time: "09:00", endTime: endTime, title: "Sync", description: "")],
                settlementData: settlement
            )
        }
        let base = pack().stableFingerprint()
        #expect(pack(endTime: "11:00").stableFingerprint() != base)
        #expect(pack(review: "r2").stableFingerprint() != base)
        #expect(pack(quote: "q2").stableFingerprint() != base)
        #expect(pack().stableFingerprint() == base)
    }

    @Test("BLEDataEncoder encodeDayPack truncates DaySummary to 180 bytes")
    func encodeDayPackTruncatesDaySummary() {
        let settlement = SettlementData(
            tasksCompleted: 0, tasksTotal: 0, pointsEarned: 0,
            petMood: "happy", summaryMessage: "", encouragementMessage: ""
        )
        let pack = DayPack(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            petDialogue: "x",
            daySummary: String(repeating: "A", count: 200),
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack)
        // Parse forward to the DaySummary length prefix (robust to trailing fields like FirstUp).
        var cursor = 5
        _ = readString(from: data, cursor: &cursor)   // PetDialogue
        cursor += 1                                    // EventCount = 0
        cursor += 1                                    // TaskCount = 0
        cursor += 10                                   // SettlementData
        #expect(data[cursor] == 180)                   // DaySummary truncated to 180 bytes
    }

    @Test("BLEDataEncoder encodeTaskInPage format excludes legacy microAction fields")
    func encodeTaskInPageFormatExcludesMicroActionFields() {
        let taskInPage = TaskInPageData(
            taskId: "task-1",
            taskTitle: "Write BLE tests",
            taskDescription: "Add comprehensive tests",
            encouragement: "Go for it!",
            focusChallengeActive: true
        )
        let data = BLEDataEncoder.encodeTaskInPage(taskInPage)

        var cursor = 0
        #expect(readString(from: data, cursor: &cursor) == "task-1")
        #expect(readString(from: data, cursor: &cursor) == "Write BLE tests")
        #expect(readString(from: data, cursor: &cursor) == "Add comprehensive tests")
        #expect(readString(from: data, cursor: &cursor) == "Go for it!")
        #expect(data[data.count - 1] == 0x01)
        #expect(cursor == data.count - 1)
    }

    @Test("String truncation at max length in BLE encoding")
    func stringTruncationAtMaxLength() {
        var data = Data()
        let longString = String(repeating: "A", count: 80)
        data.appendString(longString, maxLength: 50)
        #expect(data[0] == 50)
        #expect(data.count == 51)
    }

    @Test("String truncation does not split UTF-8 scalar")
    func stringTruncationDoesNotSplitUTF8Scalar() {
        var data = Data()
        data.appendString("Hi你", maxLength: 4)

        #expect(data[0] == 2)
        #expect(data.subdata(in: 1..<data.count) == Data("Hi".utf8))
        #expect(String(data: data.subdata(in: 1..<data.count), encoding: .utf8) == "Hi")
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
        payload.appendBigEndian(timestamp)

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

    @Test("BLEEventHandler parses variable-length EventLog batch payload")
    @MainActor
    func parseEventLogBatchPayloadVariableLength() {
        let taskId = Data("abc".utf8)
        let timestamp: UInt32 = 1_700_000_000

        var payload = Data()
        payload.append(3) // count
        payload.append(0x01) // encoderRotateUp
        payload.append(0x40) // lowBattery
        payload.append(15)
        payload.append(0x10) // enterTaskIn
        payload.append(UInt8(taskId.count))
        payload.append(taskId)
        payload.appendBigEndian(timestamp)

        let logs = BLEEventHandler.parseEventLogBatchPayload(payload)
        #expect(logs.count == 3)
        #expect(logs[0].eventType == .encoderRotateUp)
        #expect(logs[1].eventType == .lowBattery)
        #expect(logs[1].batteryLevel == 15)
        #expect(logs[2].eventType == .enterTaskIn)
        #expect(logs[2].taskId == "abc")
        #expect(Int(logs[2].timestamp.timeIntervalSince1970) == Int(timestamp))
    }

    @Test("BLEEventHandler rejects partially malformed EventLog batch payload")
    @MainActor
    func parseEventLogBatchPayloadRejectsPartialMalformedBatch() {
        var payload = Data()
        payload.append(2)
        payload.append(0x01)
        payload.append(0x10)
        payload.append(10)
        payload.append(contentsOf: Data("abc".utf8))

        let logs = BLEEventHandler.parseEventLogBatchPayload(payload)
        #expect(logs.isEmpty)
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
        payload.appendBigEndian(timestamp)

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

    @Test("fromBLEPayload lowBattery clamps level to 100")
    func fromBLEPayloadLowBatteryClampsLevel() {
        let event = EventLog.fromBLEPayload(type: 0x40, payload: Data([255]))
        #expect(event?.eventType == .lowBattery)
        #expect(event?.batteryLevel == 100)
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
        payload.appendBigEndian(timestamp)

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

    @Test("fromBLEPayload id-only event ignores trailing bytes")
    func fromBLEPayloadIdOnlyEventIgnoresTrailingBytes() {
        var payload = Data()
        payload.append(1)
        payload.append(0x41)
        payload.append(0x00)

        let event = EventLog.fromBLEPayload(type: 0x14, payload: payload)
        #expect(event?.eventType == .wheelSelect)
        #expect(event?.taskId == nil)
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

    @Test("BLEEventHandler resolves newest task when duplicate IDs exist")
    func bleEventHandlerResolvesNewestTaskByRecency() {
        let taskId = "dup-task"
        let older = TaskItem(
            id: taskId,
            title: "Old Title",
            lastModified: Date(timeIntervalSince1970: 100),
            remoteUpdatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = TaskItem(
            id: taskId,
            title: "New Title",
            lastModified: Date(timeIntervalSince1970: 110),
            remoteUpdatedAt: Date(timeIntervalSince1970: 200)
        )

        let resolved = BLEEventHandler.resolveTask(taskId: taskId, in: [older, newer])
        #expect(resolved?.title == "New Title")
    }

    @Test("BLEEventHandler resolves by lastModified when remoteUpdatedAt missing")
    func bleEventHandlerResolvesByLastModifiedFallback() {
        let taskId = "dup-task-no-remote"
        let older = TaskItem(
            id: taskId,
            title: "Old Local",
            lastModified: Date(timeIntervalSince1970: 100),
            remoteUpdatedAt: nil
        )
        let newer = TaskItem(
            id: taskId,
            title: "New Local",
            lastModified: Date(timeIntervalSince1970: 200),
            remoteUpdatedAt: nil
        )

        let resolved = BLEEventHandler.resolveTask(taskId: taskId, in: [older, newer])
        #expect(resolved?.title == "New Local")
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

    // EInkColor / 4bpp packPixelPair 测试已删（v2.5.24）：0x15 头像帧改传 PNG，
    // App 侧 Spectra 6 量化与 4bpp 打包整链路（EInkColor.swift / encodePixelData /
    // Spectra6QuantizerTests）随之移除，色彩量化改由固件端完成。

    // MARK: - ScreenConfig Tests

    // 分辨率断言 = 硬件确认的实际面板（docs/硬件需求文档 §4）：4寸 768×552 横向、7.3寸 1600×1200。
    // 旧断言 400×600 / 800×480 是早期面板型号（2026-07-04 审计 D1 对齐）。
    @Test("ScreenSize fourInch dimensions")
    func screenSizeFourInch() {
        let screen = ScreenSize.fourInch
        #expect(screen.width == 768)
        #expect(screen.height == 552)
        #expect(screen.pixelCount == 423_936)
        #expect(screen.frameBufferSize == 211_968)
        #expect(screen.maxTasks == 3)
    }

    @Test("ScreenSize sevenInch dimensions")
    func screenSizeSevenInch() {
        let screen = ScreenSize.sevenInch
        #expect(screen.width == 1600)
        #expect(screen.height == 1200)
        #expect(screen.pixelCount == 1_920_000)
        #expect(screen.frameBufferSize == 960_000)
        #expect(screen.maxTasks == 5)
    }

    // MARK: - BLEDataEncoder Custom Avatar Frame Tests (0x15, v2.7)

    @Test("encodeCustomAvatarFrame v4 carries identity metadata and KRI")
    func encodeCustomAvatarKRIFrameLayout() throws {
        let standardRGBA: [UInt8] = [
            255, 0, 0, 255,   0, 255, 0, 255,
            0, 0, 255, 255,   255, 255, 255, 128,
        ]
        let kriData = try KRIEncoder.encode(width: 2, height: 2, straightRGBA: standardRGBA)
        let avatarID = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        let payload = try BLEDataEncoder.encodeCustomAvatarFrame(
            operationID: 0x1020_3040,
            avatarID: avatarID,
            kriData: kriData
        )

        #expect(payload.count == CustomAvatarFrameV4Codec.headerLength + kriData.count)
        #expect(payload[0] == 0x04)
        #expect(try CustomAvatarFrameV4Codec.decode(payload).kriData == kriData)
    }

    @Test("Avatar KRI wire budget equals 12B header plus 800×700×4 BGRA")
    func avatarKRIWireBudget() {
        // 协议 §4.12 v4 的最大 KRI 文件长度真源：尺寸封顶即字节封顶。
        #expect(AvatarImageProcessor.maxKRIEncodedByteCount == 2_240_012)
    }

    // encodeScreenConfig 及其格式测试已删（2026-07-04 审计 D2）：该函数无发送路径、
    // BLEDataType 也没有对应帧字节，且断言的是已过时的旧面板分辨率。

    // MARK: - EventLogBatch Replay → AppState Mutation Tests

    @Test("Batch replay: completeTask marks task completed in AppState")
    @MainActor
    func batchReplayCompleteTaskMarksTaskCompleted() async {
        let taskId = "ble-replay-complete-\(UUID().uuidString)"
        let task = TaskItem(id: taskId, title: "Replay Complete Test", isCompleted: false, dueDate: nil)
        AppState.shared.addTask(task)
        defer { AppState.shared.deleteTask(task) }

        let event = EventLog(eventType: .completeTask, taskId: taskId, timestamp: Date())
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: BLEProtocolMockFocusGuardService(),
            persistenceEnabled: false
        )
        await BLEEventHandler.handleEventLogs(
            [event], service: BLEService.shared,
            focusService: focusService, isReplay: true,
            lastTimestampOverride: 0
        )

        let found = AppState.shared.tasks.first { $0.id == taskId }
        #expect(found?.isCompleted == true)
    }

    @Test("Batch replay: enterTaskIn does NOT start a focus session")
    @MainActor
    func batchReplayEnterTaskInSkipsFocusSession() async {
        let taskId = "ble-replay-enter-\(UUID().uuidString)"
        let event = EventLog(
            eventType: .enterTaskIn, taskId: taskId,
            timestamp: Date().addingTimeInterval(-7200)  // 2 hours ago
        )
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: BLEProtocolMockFocusGuardService(),
            persistenceEnabled: false
        )
        await BLEEventHandler.handleEventLogs(
            [event], service: BLEService.shared,
            focusService: focusService, isReplay: true
        )

        #expect(focusService.activeSession == nil)
    }

    @Test("Live (non-replay) enterTaskIn starts a focus session")
    @MainActor
    func liveEnterTaskInStartsFocusSession() async {
        let taskId = "ble-live-enter-\(UUID().uuidString)"
        let event = EventLog(eventType: .enterTaskIn, taskId: taskId, timestamp: Date())
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: BLEProtocolMockFocusGuardService(),
            persistenceEnabled: false
        )
        // 2026-07-04 起 live enterTaskIn 会 guard 任务存在（固件曾发空 taskId 造出
        // "Unknown Task"+溢出时长怪帧）；经 tasksOverride 注入任务，不碰 AppState.shared。
        await BLEEventHandler.handleEventLogs(
            [event], service: BLEService.shared,
            focusService: focusService, isReplay: false,
            tasksOverride: [TaskItem(id: taskId, title: "Live Enter Task")]
        )

        #expect(focusService.activeSession?.taskId == taskId)
    }

    @Test("Live enterTaskIn with empty taskId (malformed 0x10) does not start a session")
    @MainActor
    func liveEnterTaskInEmptyTaskIdSkipsSession() async {
        // 固件 EnterTaskIn payload 首字节 0x00 解析为空 taskId（协议 §8.7 问题 4 实测）——
        // 不得开会话，否则会推出 "Unknown Task"/溢出时长的 0x14 怪帧。
        let event = EventLog(eventType: .enterTaskIn, taskId: "", timestamp: Date(timeIntervalSince1970: 49))
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: BLEProtocolMockFocusGuardService(),
            persistenceEnabled: false
        )
        await BLEEventHandler.handleEventLogs(
            [event], service: BLEService.shared,
            focusService: focusService, isReplay: false,
            tasksOverride: []
        )
        #expect(focusService.activeSession == nil)
    }

    @Test("Ancient device timestamps cannot mint negative focus duration")
    @MainActor
    func ancientTimestampsClampedNonNegative() async {
        // 固件 RTC 未同步（1970 级时间戳）时：开始被夹到 now-2h，结束被 endSession 夹到
        // 不早于开始——两侧都夹住才不会写出负专注时长（Codex review P1）。
        let taskId = "ble-ancient-\(UUID().uuidString)"
        let ancient = Date(timeIntervalSince1970: 49)
        let tasks = [TaskItem(id: taskId, title: "Ancient Task")]
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: BLEProtocolMockFocusGuardService(),
            persistenceEnabled: false
        )
        await BLEEventHandler.handleEventLogs(
            [EventLog(eventType: .enterTaskIn, taskId: taskId, timestamp: ancient)],
            service: BLEService.shared, focusService: focusService, isReplay: false,
            tasksOverride: tasks
        )
        let start = focusService.activeSession?.startTime
        #expect(start != nil)
        if let start {
            #expect(start.timeIntervalSince1970 > Date().timeIntervalSince1970 - 7300)
        }

        await BLEEventHandler.handleEventLogs(
            [EventLog(eventType: .completeTask, taskId: taskId, timestamp: ancient)],
            service: BLEService.shared, focusService: focusService, isReplay: false,
            tasksOverride: tasks
        )
        await focusService.waitForPendingPersistenceForTesting()
        let ended = focusService.todaySessions.last { $0.taskId == taskId }
        #expect(ended != nil)
        if let ended, let end = ended.endTime {
            #expect(end >= ended.startTime)
            #expect(ended.earnedEnergyBottles >= 0)
        }
    }

    @Test("BLEDataEncoder encodeDayPack with sevenInch allows 5 tasks")
    func encodeDayPackSevenInchTaskLimit() {
        let settlement = SettlementData(
            tasksCompleted: 0, tasksTotal: 5, pointsEarned: 0,
            petMood: "happy",
            summaryMessage: "s", encouragementMessage: "e"
        )
        let tasks = (0..<5).map { i in
            TaskSummary(id: "t\(i)", title: "Task \(i)", isCompleted: false, priority: 1)
        }
        let pack = DayPack(
            date: Date(),
            deviceMode: .interactive,
            petDialogue: "hi",
            events: [],
            topTasks: tasks,
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack, screenSize: .sevenInch)

        // Find task count byte: after header(5) + PetDialogue + EventCount(0 events → no bodies)
        // The task count should be 5 (7.3" allows up to 5)
        let headerSize = 5
        let dialogueSize = 1 + "hi".utf8.count
        let eventCountSize = 1
        let taskCountOffset = headerSize + dialogueSize + eventCountSize
        #expect(data[taskCountOffset] == 5)
    }

    @Test("BLEDataEncoder encodeDayPack clamps negative settlement counters")
    func encodeDayPackClampsNegativeSettlementCounters() {
        let settlement = SettlementData(
            tasksCompleted: -1,
            tasksTotal: -1,
            pointsEarned: -10,
            petMood: "happy",
            summaryMessage: "s",
            encouragementMessage: "e",
            totalFocusMinutes: -20,
            focusSessionCount: -1,
            longestFocusMinutes: -30,
            interruptionCount: -1
        )
        let pack = DayPack(
            date: Date(),
            deviceMode: .interactive,
            petDialogue: "",
            events: [],
            topTasks: [],
            settlementData: settlement
        )
        let data = BLEDataEncoder.encodeDayPack(pack)

        // Header(5) + PetDialogue empty(1) + EventCount=0(1) + TaskCount=0(1) = 8
        let cursor = 8
        #expect(data[cursor] == 0)
        #expect(data[cursor + 1] == 0)
        #expect(data[cursor + 2] == 0)
        #expect(data[cursor + 3] == 0)
        #expect(data[cursor + 4] == 0)
        #expect(data[cursor + 5] == 0)
        #expect(data[cursor + 6] == 0)
        #expect(data[cursor + 7] == 0)
        #expect(data[cursor + 8] == 0)
        #expect(data[cursor + 9] == 0)
    }

    @Test("FocusStatus clamps negative counters to zero")
    func focusStatusClampsNegativeCountersToZero() {
        let data = BLEDataEncoder.encodeFocusStatus(
            phase: .building,
            energyBottles: -3,
            elapsedMinutes: -20,
            taskTitle: "Task",
            segmentMinutes: -5
        )

        #expect(data[0] == 2)
        #expect(data[1] == 0)
        #expect(data[2] == 0)
        #expect(data[3] == 0)
        // SegmentMinutes (2B BE) is appended after the 1-byte length + "Task" (offsets 9-10)
        // and clamps the negative value to zero.
        #expect(data.count == 11)
        #expect(data[9] == 0)
        #expect(data[10] == 0)
    }

    // MARK: - OTA Protocol Tests

    @Test("OTAReboot byte value is 0x18")
    func otaRebootByteValue() {
        #expect(BLEDataType.otaReboot.rawValue == 0x18)
    }

    @Test("OTAResult rawByte is 0x18")
    func otaResultRawByte() {
        #expect(EventLogType.otaResult.rawByte == 0x18)
    }

    @Test("OTAResult round-trips through rawByte init")
    func otaResultRawByteInit() {
        #expect(EventLogType(rawByte: 0x18) == .otaResult)
    }

    @Test("OTAResult parses 1-byte status code from payload")
    func otaResultParsesStatusCode() {
        let log = EventLog.fromBLEPayload(type: 0x18, payload: Data([0x01]))
        #expect(log?.eventType == .otaResult)
        #expect(log?.value == 1)
    }

    @Test("OTAResult falls back to 0xFF on empty payload")
    func otaResultEmptyPayloadFallback() {
        let log = EventLog.fromBLEPayload(type: 0x18, payload: Data())
        #expect(log?.value == 0xFF)
    }

    // MARK: - DeviceWake Firmware Version (v2.5.19)

    @Test("DeviceWake parses firmware version from 4-byte payload")
    func deviceWakeParsesFirmwareVersion() {
        let log = EventLog.fromBLEPayload(type: 0x30, payload: Data([0x64, 0x01, 0x02, 0x03]))
        #expect(log?.value == 100)
        #expect(log?.firmwareVersion == FirmwareVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("DeviceWake with legacy 1-byte payload has nil firmware version")
    func deviceWakeLegacyPayloadNoVersion() {
        let log = EventLog.fromBLEPayload(type: 0x30, payload: Data([0x64]))
        #expect(log?.value == 100)
        #expect(log?.firmwareVersion == nil)
    }

    @Test("DeviceWake with 2-3 byte payload treats version as absent")
    func deviceWakePartialPayloadNoVersion() {
        let log = EventLog.fromBLEPayload(type: 0x30, payload: Data([0x64, 0x01]))
        #expect(log?.value == 100)
        #expect(log?.firmwareVersion == nil)
    }

    @Test("FirmwareVersion renders as Major.Minor.Patch")
    func firmwareVersionDescription() {
        let v = FirmwareVersion(major: 1, minor: 12, patch: 3)
        #expect(v.description == "1.12.3")
    }
}

// MARK: - Shared Mock

@MainActor
private final class BLEProtocolMockFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .notDetermined
    var isDeepFocusFeatureEnabled = false
    var isDeepFocusCapable = false
    var canShowDeepFocusEntry: Bool { false }
    var selectedApplicationCount = 0
    var isPickerPresented = false
    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { .notDetermined }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}

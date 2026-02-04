import Foundation
import Testing
@testable import KiroFeature

@Suite("BLE Protocol Tests")
struct BLEProtocolTests {

    @Test("CRC16-CCITT-FALSE known vector")
    func crc16KnownVector() throws {
        let data = Data("123456789".utf8)
        let crc = CRC16.ccittFalse(data)
        #expect(crc == 0x29B1)
    }

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

    @Test("EventLog record parsing")
    func eventLogParsing() throws {
        let timestamp: UInt32 = 1_700_000_100
        let value: Int16 = 3

        var data = Data()
        data.append(EventLogType.encoderShortPress.rawByte)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: value.bigEndian) { Array($0) })

        let log = EventLog.parseRecord(from: data)
        #expect(log?.eventType == .encoderShortPress)
        #expect(Int(log?.timestamp.timeIntervalSince1970 ?? 0) == Int(timestamp))
        #expect(log?.value == Int(value))
    }
}

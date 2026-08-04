import Foundation
import Testing
@testable import KiroleFeature

@Suite("Daily content transaction")
struct DailyContentTransactionTests {
    @Test("A complete daily package round-trips without an eight-event limit")
    func completePackageRoundTrip() throws {
        let package = makePackage(eventCount: 19)
        let transaction = DailyContentTransaction(
            version: DailyContentVersion(epoch: 21, revision: 4),
            package: package
        )

        let encoded = try DailyContentCodec.encodeTransaction(transaction)
        let decoded = try DailyContentCodec.decodeTransaction(encoded)
        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.dailyContentTransaction.rawValue,
            messageId: 0x2401,
            payload: encoded,
            maxChunkSize: 37
        )
        let assembler = BLEPacketAssembler()
        var reassembled: BLEReceivedMessage?
        for packet in packets {
            reassembled = assembler.append(packetData: packet) ?? reassembled
        }
        var firmware = SimulatedDailyContentFirmware()
        let acknowledgement = try firmware.apply(payload: #require(reassembled).payload)

        #expect(decoded == transaction)
        #expect(packets.count > 8)
        #expect(reassembled?.type == BLEDataType.dailyContentTransaction.rawValue)
        #expect(acknowledgement.result == .committed)
        #expect(firmware.committedPackage == package)
        #expect(decoded.package.events.count == 19)
        #expect(decoded.package.morningDialogue == "A gentle morning start.")
        #expect(decoded.package.idleDialogue == "There is room to breathe.")
        #expect(decoded.package.closingDialogue == "The day can settle now.")
        #expect(decoded.package.screensaverQuote == "Rest belongs to the work.")
        #expect(decoded.package.settlementReview == "Today had a steady shape.")
        #expect(decoded.package.settlementQuote == "Keep the useful part.")
        #expect(BLEDataType.dailyContentTransaction.rawValue == 0x24)
    }

    @Test("Only events on the device local date enter the package source")
    func onlyLocalDateEventsAreSelected() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 12
        )))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let events = [
            makeEvent(id: "yesterday", start: yesterday),
            makeEvent(id: "today", start: now),
            makeEvent(id: "tomorrow", start: tomorrow),
        ]

        let selected = DailyContentSource.todayEvents(
            from: events,
            at: now,
            calendar: calendar
        )

        #expect(selected.map(\.id) == ["today"])
    }

    @Test("Today's events are capped at the earliest twenty by start time")
    func todayEventsKeepsTheEarliestTwentyByStartTime() throws {
        // 排序在截断之前：乱序传入 25 条，留下的必须是最早的 20 条并按开始时间升序，
        // 而不是任意 20 条再排序。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 0
        )))
        let shuffledOffsets = [24, 3, 17, 0, 9, 22, 5, 14, 1, 20, 11, 7, 18, 2,
                               23, 8, 15, 4, 12, 21, 6, 19, 10, 16, 13]
        let events = shuffledOffsets.map { offset in
            makeEvent(
                id: "event-\(String(format: "%02d", offset))",
                start: now.addingTimeInterval(Double(offset) * 1_800)
            )
        }

        let selected = DailyContentSource.todayEvents(from: events, at: now, calendar: calendar)

        #expect(selected.count == DailyContentSource.maxEvents)
        #expect(selected.map(\.id) == (0..<20).map { "event-\(String(format: "%02d", $0))" })
        #expect(!selected.contains { $0.id == "event-24" })
    }

    @Test("A corrupted replacement never changes the committed package")
    func corruptedReplacementKeepsCommittedPackage() throws {
        var firmware = SimulatedDailyContentFirmware()
        let first = DailyContentTransaction(
            version: DailyContentVersion(epoch: 7, revision: 1),
            package: makePackage(eventCount: 3, marker: "first")
        )
        let replacement = DailyContentTransaction(
            version: DailyContentVersion(epoch: 7, revision: 2),
            package: makePackage(eventCount: 14, marker: "replacement")
        )
        let firstPayload = try DailyContentCodec.encodeTransaction(first)
        _ = try firmware.apply(payload: firstPayload)

        var corrupted = try DailyContentCodec.encodeTransaction(replacement)
        corrupted[corrupted.count / 2] ^= 0x01

        #expect(throws: DailyContentCodecError.self) {
            try firmware.apply(payload: corrupted)
        }
        #expect(firmware.committedVersion == first.version)
        #expect(firmware.committedPackage == first.package)
    }

    @Test("The acknowledgement names the exact committed version and CRC")
    func acknowledgementRoundTrip() throws {
        let transaction = DailyContentTransaction(
            version: DailyContentVersion(epoch: 9, revision: 2),
            package: makePackage(eventCount: 1)
        )
        let state = try DailyContentCodec.committedState(for: transaction)
        let acknowledgement = DailyContentCommitAcknowledgement(
            version: state.version,
            result: .committed,
            contentCRC32: state.contentCRC32
        )

        #expect(
            try DailyContentCodec.decodeAcknowledgement(
                DailyContentCodec.encodeAcknowledgement(acknowledgement)
            ) == acknowledgement
        )
    }

    @MainActor
    @Test("A failed delivery retries the exact complete transaction once")
    func failedDeliveryRetriesWholeTransaction() async throws {
        let transaction = DailyContentTransaction(
            version: DailyContentVersion(epoch: 11, revision: 5),
            package: makePackage(eventCount: 17)
        )
        let expectedState = try DailyContentCodec.committedState(for: transaction)
        var attempts: [DailyContentTransaction] = []
        let retrier = DailyContentDeliveryRetrier(retrySleeper: { _ in })

        let acknowledgement = try await retrier.deliver(transaction) { frozen in
            attempts.append(frozen)
            if attempts.count == 1 { throw TestDailyContentDeliveryError.failed }
            return DailyContentCommitAcknowledgement(
                version: expectedState.version,
                result: .committed,
                contentCRC32: expectedState.contentCRC32
            )
        }

        #expect(attempts == [transaction, transaction])
        #expect(acknowledgement.result == .committed)
    }

    @MainActor
    @Test("A 0x24 commit result is routed before EventLog parsing")
    func acknowledgementRoutesToBLEService() async {
        let expected = DailyContentCommitAcknowledgement(
            version: DailyContentVersion(epoch: 9, revision: 3),
            result: .committed,
            contentCRC32: 0xCBF4_3926
        )
        var received: DailyContentCommitAcknowledgement?
        BLEService.shared.onDailyContentCommitAcknowledgement = { received = $0 }
        defer { BLEService.shared.onDailyContentCommitAcknowledgement = nil }

        await BLEEventHandler.handleReceivedPayload(
            BLEReceivedMessage(
                type: BLEDataType.dailyContentTransaction.rawValue,
                payload: DailyContentCodec.encodeAcknowledgement(expected)
            ),
            service: .shared
        )

        #expect(received == expected)
    }
}

private enum TestDailyContentDeliveryError: Error {
    case failed
}

private func makePackage(eventCount: Int, marker: String = "event") -> DailyContentPackage {
    let events: [DailyContentEvent] = (0..<eventCount).map { index in
        let start = UInt64(1_800_000_000 + index * 3_600)
        let end = UInt64(1_800_001_800 + index * 3_600)
        return DailyContentEvent(
            eventID: "\(marker)-\(index)",
            startTimestamp: start,
            endTimestamp: end,
            isAllDay: false,
            title: "Event \(index)",
            detail: "Details \(index)",
            category: .deepWork,
            companionDialogue: "One clear moment for event \(index).",
            supportText: "Choose one small piece to begin."
        )
    }
    return DailyContentPackage(
        localDate: DailyContentDate(year: 2026, month: 8, day: 3),
        morningDialogue: "A gentle morning start.",
        idleDialogue: "There is room to breathe.",
        closingDialogue: "The day can settle now.",
        daySummary: "A full but manageable day.",
        screensaverQuote: "Rest belongs to the work.",
        screensaverAuthor: "Joy",
        settlementReview: "Today had a steady shape.",
        settlementQuote: "Keep the useful part.",
        events: events
    )
}

private func makeEvent(id: String, start: Date) -> CalendarEvent {
    CalendarEvent(
        id: id,
        title: id,
        startTime: start,
        endTime: start.addingTimeInterval(1_800)
    )
}

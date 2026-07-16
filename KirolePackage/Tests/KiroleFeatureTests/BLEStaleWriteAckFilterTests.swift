import Testing
@testable import KiroleFeature

/// BLEStaleWriteAckFilter：写超时后迟到 ACK 的丢弃记账（BLEService.didWriteValueFor 的决策核心）。
@Suite("BLE Stale Write ACK Filter")
struct BLEStaleWriteAckFilterTests {
    @Test("无被弃写时 ACK 正常放行")
    func ackWithNoAbandonedWritesPasses() {
        var filter = BLEStaleWriteAckFilter()

        #expect(filter.shouldDropIncomingAck() == false)
        #expect(filter.pendingStaleAcks == 0)
    }

    @Test("超时被弃后第一个迟到 ACK 被丢，随后的真 ACK 放行")
    func lateAckAfterTimeoutDroppedOnceThenNextPasses() {
        var filter = BLEStaleWriteAckFilter()

        filter.markAbandonedWrite()

        #expect(filter.shouldDropIncomingAck() == true)
        #expect(filter.shouldDropIncomingAck() == false)
    }

    @Test("两次被弃恰好丢两个 ACK，不多不少")
    func twoAbandonsDropTwoAcks() {
        var filter = BLEStaleWriteAckFilter()

        filter.markAbandonedWrite()
        filter.markAbandonedWrite()

        #expect(filter.shouldDropIncomingAck() == true)
        #expect(filter.shouldDropIncomingAck() == true)
        #expect(filter.shouldDropIncomingAck() == false)
    }

    @Test("断连 reset 清零记账，不跨连接吞 ACK")
    func resetClearsPendingStaleAcks() {
        var filter = BLEStaleWriteAckFilter()
        filter.markAbandonedWrite()

        filter.reset()

        #expect(filter.pendingStaleAcks == 0)
        #expect(filter.shouldDropIncomingAck() == false)
    }
}

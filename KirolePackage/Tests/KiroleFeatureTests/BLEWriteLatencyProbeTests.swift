import Foundation
import Testing
@_spi(KiroleInternal) @testable import KiroleFeature
@testable import KiroleInternalBLE

@Suite("BLE write latency probe")
struct BLEWriteLatencyProbeTests {
    /// The probe sits on every GATT write. Customer builds install nothing, so the uninstalled
    /// path is the one that ships — it must be inert, not merely harmless-looking.
    @Test("Recording without an installed recorder is a no-op")
    @MainActor
    func uninstalledProbeIsInert() {
        BLEWriteLatencyProbe.uninstall()
        BLEWriteLatencyProbe.record(packetType: 0x03, latency: .seconds(1), outcome: .acknowledged)
        BLEWriteLatencyProbe.record(packetType: nil, latency: .seconds(30), outcome: .timedOut)
    }

    @Test("Installed recorder receives every write outcome")
    @MainActor
    func installedRecorderReceivesSamples() {
        final class Spy: BLEWriteLatencyRecording {
            var samples: [(UInt8?, Double, BLEWriteOutcome)] = []
            func recordWriteAck(packetType: UInt8?, milliseconds: Double, outcome: BLEWriteOutcome) {
                samples.append((packetType, milliseconds, outcome))
            }
        }
        let spy = Spy()
        BLEWriteLatencyProbe.install(spy)
        defer { BLEWriteLatencyProbe.uninstall() }

        BLEWriteLatencyProbe.record(packetType: 0x03, latency: .milliseconds(250), outcome: .acknowledged)
        BLEWriteLatencyProbe.record(packetType: 0x10, latency: .seconds(5), outcome: .timedOut)

        #expect(spy.samples.count == 2)
        #expect(spy.samples[0].0 == 0x03)
        #expect(abs(spy.samples[0].1 - 250) < 0.001)
        #expect(spy.samples[0].2 == .acknowledged)
        #expect(spy.samples[1].2 == .timedOut)
    }

    /// `Duration` stores seconds and attoseconds separately; reading either alone silently loses
    /// the rest, which would quietly corrupt every measurement this probe exists to produce.
    @Test("Duration converts to milliseconds across both components")
    func durationConversion() {
        #expect(abs(BLEWriteLatencyProbe.milliseconds(.seconds(12)) - 12_000) < 0.001)
        #expect(abs(BLEWriteLatencyProbe.milliseconds(.milliseconds(1_500)) - 1_500) < 0.001)
        #expect(abs(BLEWriteLatencyProbe.milliseconds(.microseconds(500)) - 0.5) < 0.001)
    }

    /// Bucket edges are the decision boundaries — 5s is today's timeout, ~12s a 7.3" full refresh.
    /// An off-by-one here would misreport exactly the samples the timeout choice hinges on.
    @Test("Bucket edges are exclusive upper bounds")
    func bucketBoundaries() {
        // Edges: 100, 500, 1000, 2000, 5000, 8000, 12000, 15000, 20000
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 0) == 0)
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 99.9) == 0)
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 100) == 1)
        // A write at exactly today's 5s timeout must not be counted as "under 5s".
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 4_999) == 4)
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 5_000) == 5)
        // Around a full refresh.
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 11_999) == 6)
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 12_000) == 7)
        // Overflow bucket.
        #expect(BLEWriteLatencyRecorder.bucketIndex(for: 25_000) == 9)
    }

    @Test("Summary renders only non-empty buckets")
    func summaryRendersSparsely() {
        var buckets = [Int](repeating: 0, count: 10)
        #expect(BLEWriteLatencyRecorder.describe(buckets) == "(none)")

        buckets[0] = 380
        buckets[6] = 2
        let text = BLEWriteLatencyRecorder.describe(buckets)
        #expect(text.contains("0-100ms:380"))
        #expect(text.contains("8000-12000ms:2"))
        #expect(!text.contains(":0"))
    }
}

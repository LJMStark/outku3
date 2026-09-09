#if KIROLE_INTERNAL || KIROLE_INTERNAL_BLE_MODULE
import Foundation
import os
@_spi(KiroleInternal) import KiroleFeature

/// Upper edges in milliseconds; anything above the last edge lands in a final overflow bucket.
///
/// The edges sit on the values actually under discussion — 5s is today's write timeout, ~12s is a
/// 7.3" E-ink full refresh, 15s/20s are the candidates — so the distribution answers the question
/// directly instead of needing to be re-bucketed later. File scope keeps them out of the recorder's
/// main-actor isolation, so `WriteLatencyStats` can stay a plain value type.
private let bucketEdgesMs: [Double] = [100, 500, 1_000, 2_000, 5_000, 8_000, 12_000, 15_000, 20_000]

private struct WriteLatencyStats {
    var acknowledged = 0
    var timedOut = 0
    var failed = 0
    var maxAckMilliseconds: Double = 0
    var buckets = [Int](repeating: 0, count: bucketEdgesMs.count + 1)
}

/// Measures how long the firmware actually takes to ACK a GATT write, so the write timeout can be
/// chosen from device data instead of from a comment.
///
/// The open question: `BLEService`'s write-ACK timeout is a hardcoded 5s, and an unmerged
/// stability branch argued for 20s because a 7.3" E-ink full refresh takes ~12s, during which the
/// firmware may not answer at all — making 5s a false-positive timeout that then gets amplified
/// into a failed sync round. Raising it is not free either: a link that stays up while the device
/// is wedged takes that much longer to fail. Measure before picking.
///
/// **Fixed-bucket histogram, not a sample list.** A custom-avatar transfer can be ~4,472 packets;
/// keeping per-write samples would grow without bound during exactly the transfers worth
/// measuring, and the allocation churn would perturb what is being measured.
@MainActor
final class BLEWriteLatencyRecorder: BLEWriteLatencyRecording {
    /// Internal-only diagnostic category, registered in the INTERNAL_ONLY list of
    /// scripts/verify-release-boundary.sh — it must never reach the App Store binary.
    ///
    /// **Kebab-case on purpose** (same as `release-channel` in InternalBuildBoundary). The gate
    /// does a raw byte-substring search, and this probe's seam types — `BLEWriteLatencyProbe`,
    /// `BLEWriteLatencyRecording` — live in KiroleFeature, which *is* compiled into the customer
    /// binary. A PascalCase category sharing their word stem would be found in those symbol names
    /// and fail the gate forever, with nothing actually leaking. A category no Swift identifier can
    /// spell keeps the check meaning what it says.
    private static let logger = Logger(subsystem: "com.kirole.app", category: "ble-write-ack")

    /// Summaries are periodic: one line per write would emit thousands during an avatar transfer.
    private static let summaryInterval = 50

    /// Keyed by packet type — a 0x03 Schedule write and one chunk of a 2 MB avatar are different
    /// questions, and pooling them would hide whichever is rarer.
    private var statsByType: [UInt8: WriteLatencyStats] = [:]
    private var samplesSinceSummary = 0

    static func install() {
        BLEWriteLatencyProbe.install(BLEWriteLatencyRecorder())
        logger.info("BLEWriteLatency recorder installed")
    }

    func recordWriteAck(packetType: UInt8?, milliseconds: Double, outcome: BLEWriteOutcome) {
        // 0xFF stands in for "no type byte", which only happens on an empty packet.
        let key = packetType ?? 0xFF
        var stats = statsByType[key] ?? WriteLatencyStats()

        switch outcome {
        case .acknowledged:
            stats.acknowledged += 1
            stats.maxAckMilliseconds = max(stats.maxAckMilliseconds, milliseconds)
            stats.buckets[Self.bucketIndex(for: milliseconds)] += 1
        case .timedOut:
            stats.timedOut += 1
        case .failed:
            // Usually the link went away mid-write; says nothing about firmware latency, so it is
            // counted but deliberately kept out of the histogram and the max.
            stats.failed += 1
        }
        statsByType[key] = stats

        // A timeout is the event this probe exists to catch — never let it wait for a summary.
        if outcome == .timedOut {
            Self.logger.error(
                "write TIMEOUT type=0x\(String(format: "%02X", key), privacy: .public) after \(Int(milliseconds), privacy: .public)ms"
            )
            logSummary()
            return
        }

        samplesSinceSummary += 1
        if samplesSinceSummary >= Self.summaryInterval {
            logSummary()
        }
    }

    /// One line per packet type. Safe to call from internal debug UI.
    func logSummary() {
        samplesSinceSummary = 0
        for (type, stats) in statsByType.sorted(by: { $0.key < $1.key }) {
            Self.logger.notice(
                """
                type=0x\(String(format: "%02X", type), privacy: .public) \
                ack=\(stats.acknowledged, privacy: .public) \
                timeout=\(stats.timedOut, privacy: .public) \
                failed=\(stats.failed, privacy: .public) \
                maxAck=\(Int(stats.maxAckMilliseconds), privacy: .public)ms \
                dist=\(Self.describe(stats.buckets), privacy: .public)
                """
            )
        }
    }

    nonisolated static func bucketIndex(for milliseconds: Double) -> Int {
        for (index, edge) in bucketEdgesMs.enumerated() where milliseconds < edge {
            return index
        }
        return bucketEdgesMs.count
    }

    /// Renders only non-empty buckets, so the line stays readable when nearly every write is fast.
    nonisolated static func describe(_ buckets: [Int]) -> String {
        var parts: [String] = []
        var lower = 0.0
        for (index, count) in buckets.enumerated() {
            defer { if index < bucketEdgesMs.count { lower = bucketEdgesMs[index] } }
            guard count > 0 else { continue }
            let label = index < bucketEdgesMs.count
                ? "\(Int(lower))-\(Int(bucketEdgesMs[index]))ms"
                : ">\(Int(bucketEdgesMs[bucketEdgesMs.count - 1]))ms"
            parts.append("\(label):\(count)")
        }
        return parts.isEmpty ? "(none)" : parts.joined(separator: " ")
    }
}
#endif

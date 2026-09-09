import Foundation

/// How a GATT write ended, from the writer's point of view.
///
/// Only `.acknowledged` samples answer the question this probe exists for — "how long does the
/// firmware actually take to ACK?" — so the outcome is recorded rather than filtered at the call
/// site. `.timedOut` samples are censored at the timeout value and would drag any average toward
/// it; `.failed` samples usually mean the link went away mid-write and say nothing about firmware
/// latency at all.
@_spi(KiroleInternal)
public enum BLEWriteOutcome: Sendable {
    case acknowledged
    case timedOut
    case failed
}

/// Internal TestFlight installs a recorder at startup. App Store builds leave this empty, so the
/// probe compiles to a nil check on a path that already awaits CoreBluetooth — see
/// `BLEInternalToolsRuntime` for the same seam applied to control-flow tools.
///
/// This is deliberately *not* part of `BLEInternalToolsControlling`: every method on that protocol
/// changes BLE behaviour, while this one only observes. Keeping them apart means installing a
/// measurement cannot accidentally alter the link.
@_spi(KiroleInternal)
@MainActor
public protocol BLEWriteLatencyRecording: AnyObject {
    func recordWriteAck(packetType: UInt8?, milliseconds: Double, outcome: BLEWriteOutcome)
}

@_spi(KiroleInternal)
@MainActor
public enum BLEWriteLatencyProbe {
    private static var recorder: (any BLEWriteLatencyRecording)?

    public static func install(_ recorder: any BLEWriteLatencyRecording) {
        self.recorder = recorder
    }

    public static func uninstall() {
        recorder = nil
    }

    /// No-op unless an internal build installed a recorder.
    static func record(packetType: UInt8?, latency: Duration, outcome: BLEWriteOutcome) {
        guard let recorder else { return }
        recorder.recordWriteAck(
            packetType: packetType,
            milliseconds: Self.milliseconds(latency),
            outcome: outcome
        )
    }

    /// `Duration` carries seconds + attoseconds; neither alone is the elapsed time.
    /// Pure arithmetic — `nonisolated` so it needs no actor hop and stays testable off-main.
    nonisolated static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}

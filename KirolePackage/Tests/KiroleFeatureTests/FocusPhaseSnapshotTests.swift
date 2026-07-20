import Foundation
import Testing
@testable import KiroleFeature

/// v2.5.31 回归：活跃专注会话对外（0x14 / UI）恒不报 idle——
/// 会话第 0 分钟与打断清零瞬间都属 warmup；Phase 0 = idle 仅表示"无会话"
/// （固件以 Phase≠0 判会话活跃，协议 §8.7 问题 5 口径）。
@Suite("Focus Phase Snapshot")
struct FocusPhaseSnapshotTests {

    @Test("活跃会话第 0 分钟 phase = warmup（不发 idle）")
    @MainActor func minuteZeroReportsWarmup() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(taskId: "t-1", taskTitle: "Write spec", startTime: start)
        let snapshot = FocusSessionService.shared.progressSnapshot(
            for: session, now: start.addingTimeInterval(5)
        )
        #expect(snapshot.segmentMinutes == 0)
        #expect(snapshot.phase == .warmup)
    }

    @Test("无会话仍为 idle（真 idle 只走 nil 分支）")
    @MainActor func nilSessionStaysIdle() {
        let snapshot = FocusSessionService.shared.progressSnapshot(for: nil)
        #expect(snapshot.phase == .idle)
    }

    @Test("FocusPhase.from 原始映射保持不变（0 分钟裸值仍 idle，钳制在快照层）")
    func rawMappingUnchanged() {
        #expect(FocusPhase.from(elapsedMinutes: 0) == .idle)
        #expect(FocusPhase.from(elapsedMinutes: 1) == .warmup)
        #expect(FocusPhase.from(elapsedMinutes: 6) == .building)
        #expect(FocusPhase.from(elapsedMinutes: 16) == .deep)
    }
}

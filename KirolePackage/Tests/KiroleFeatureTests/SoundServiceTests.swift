import Testing
@testable import KiroleFeature

@Suite("SoundService")
struct SoundServiceTests {
    @Test func everyCueUsesASystemSoundID() {
        let cues: [SoundType] = [
            .taskComplete,
            .taskUncomplete,
            .petEvolution,
            .petInteraction,
            .sceneMilestone,
            .buttonTap,
            .notification,
        ]

        for cue in cues {
            #expect(cue.systemSoundID > 0)
        }
    }

    @Test func taskCuesUseDistinctSystemSounds() {
        #expect(SoundType.taskComplete.systemSoundID == 1057)
        #expect(SoundType.taskUncomplete.systemSoundID == 1104)
        #expect(SoundType.sceneMilestone.systemSoundID == 1026)
    }
}

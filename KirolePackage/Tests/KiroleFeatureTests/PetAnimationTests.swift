import Testing
import Foundation
import SwiftUI
@testable import KiroleFeature

// MARK: - Pet Animation Tests

@Suite("Pet Animation Tests", .serialized)
struct PetAnimationTests {

    // MARK: - Mood State Tests

    @Suite("Mood Transitions")
    struct MoodTransitionTests {

        @Test("All pet moods are valid animation states")
        func allMoodsExist() {
            let moods = PetMood.allCases
            #expect(moods.count == 5)
            #expect(moods.contains(.happy))
            #expect(moods.contains(.excited))
            #expect(moods.contains(.focused))
            #expect(moods.contains(.sleepy))
            #expect(moods.contains(.missing))
        }

        @Test("Pet mood can be changed on AppState")
        @MainActor
        func moodCanChange() {
            let state = AppState.makeForTesting()
            let originalMood = state.pet.mood

            state.pet.mood = .sleepy
            #expect(state.pet.mood == .sleepy)

            state.pet.mood = .excited
            #expect(state.pet.mood == .excited)

            // Restore
            state.pet.mood = originalMood
        }
    }

    // MARK: - Scene Tests

    @Suite("Scene Transitions")
    struct SceneTransitionTests {

        @Test("All pet scenes are available")
        func allScenesExist() {
            let scenes = PetScene.allCases
            #expect(scenes.count == 4)
            #expect(scenes.contains(.indoor))
            #expect(scenes.contains(.outdoor))
            #expect(scenes.contains(.night))
            #expect(scenes.contains(.work))
        }

        @Test("Pet scene can be changed")
        @MainActor
        func sceneCanChange() {
            let state = AppState.makeForTesting()
            let originalScene = state.pet.scene

            state.pet.scene = .night
            #expect(state.pet.scene == .night)

            state.pet.scene = .outdoor
            #expect(state.pet.scene == .outdoor)

            // Restore
            state.pet.scene = originalScene
        }
    }

}

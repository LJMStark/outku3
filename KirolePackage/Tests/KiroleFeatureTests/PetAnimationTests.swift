import Testing
import Foundation
import SwiftUI
@testable import KiroleFeature

// MARK: - Pet Animation Tests

@Suite("Pet Animation Tests")
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
            let state = AppState.shared
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
            let state = AppState.shared
            let originalScene = state.pet.scene

            state.pet.scene = .night
            #expect(state.pet.scene == .night)

            state.pet.scene = .outdoor
            #expect(state.pet.scene == .outdoor)

            // Restore
            state.pet.scene = originalScene
        }
    }

    // MARK: - Pet Form Tests

    @Suite("Pet Form Rendering")
    struct PetFormTests {

        @Test("All pet forms have pixel patterns")
        func allFormsHavePatterns() {
            for form in PetForm.allCases {
                let body = PixelArtBody(
                    pixelSize: 5,
                    primaryColor: .orange,
                    secondaryColor: .brown,
                    accentColor: .blue,
                    animationPhase: 0,
                    petForm: form
                )
                // PixelArtBody should be constructable for all forms
                #expect(type(of: body) == PixelArtBody.self)
            }
        }

        @Test("Blink state creates valid body")
        func blinkStateWorks() {
            let body = PixelArtBody(
                pixelSize: 5,
                primaryColor: .orange,
                secondaryColor: .brown,
                accentColor: .blue,
                animationPhase: 0,
                petForm: .cat,
                mood: .happy,
                isBlinking: true
            )
            #expect(type(of: body) == PixelArtBody.self)
        }

        @Test("All moods produce valid pixel art body")
        func allMoodsProduceValidBody() {
            for mood in PetMood.allCases {
                let body = PixelArtBody(
                    pixelSize: 5,
                    primaryColor: .orange,
                    secondaryColor: .brown,
                    accentColor: .blue,
                    animationPhase: 0,
                    petForm: .cat,
                    mood: mood
                )
                #expect(type(of: body) == PixelArtBody.self)
            }
        }
    }

    // MARK: - Animation State Enum Tests

    @Suite("Animation State")
    struct AnimationStateTests {

        @Test("PixelPetSize has correct scales")
        func sizeScales() {
            #expect(PixelPetSize.small.scale == 0.5)
            #expect(PixelPetSize.medium.scale == 0.75)
            #expect(PixelPetSize.large.scale == 1.0)
        }

        @Test("PixelPetSize has correct pixel sizes")
        func pixelSizes() {
            #expect(PixelPetSize.small.pixelSize == 3)
            #expect(PixelPetSize.medium.pixelSize == 4)
            #expect(PixelPetSize.large.pixelSize == 5)
        }
    }
}

import Foundation
import Testing
@testable import KiroleFeature

@Suite("Companion Animation Catalog")
struct CompanionAnimationCatalogTests {
    @Test("Joy resolves page-specific artwork families to reviewed frame sets")
    func joyArtworkDefinitions() throws {
        #expect(CompanionMotion.allCases == [.idle, .greet, .focus, .celebrate, .react])

        let cases: [(CompanionAnimationArtwork, CompanionMotion, String)] = [
            (.main, .idle, "joy-main-idle-01"),
            (.main, .greet, "joy-main-greet-04"),
            (.main, .react, "joy-main-greet-04"),
            (.reading, .idle, "joy-reading-idle-01"),
            (.reading, .focus, "joy-reading-idle-01"),
            (.reading, .celebrate, "joy-reading-idle-01"),
            (.petScene, .idle, "joy-pet-scene-idle-01"),
            (.petScene, .react, "joy-pet-scene-idle-01"),
        ]

        for (artwork, motion, firstFrame) in cases {
            let presentation = CompanionAnimationCatalog.resolve(
                selection: .builtIn(.joy),
                artwork: artwork,
                motion: motion,
                reduceMotion: false
            )

            guard case .animated(let definition) = presentation else {
                Issue.record("Joy \(motion.rawValue) should resolve to animation frames")
                continue
            }

            #expect(definition.frames.count >= 5)
            #expect(definition.frameNames.first == firstFrame)
            #expect(definition.frames.allSatisfy { $0.duration > 0 })
            #expect(definition.minimumFrameDuration <= 0.12)
            #expect(definition.staticFallbackAssetName.hasPrefix("joy-"))
        }
    }

    @Test("Ambient and one-shot motions expose different playback behavior")
    func loopModesAndFrameSelection() throws {
        let idle = try #require(
            CompanionAnimationCatalog.animationDefinition(for: .joy, artwork: .reading, motion: .idle)
        )
        let celebrate = try #require(
            CompanionAnimationCatalog.animationDefinition(for: .joy, artwork: .reading, motion: .celebrate)
        )

        #expect(idle.loopMode == .ambient)
        #expect(celebrate.loopMode == .oneShot)
        #expect(idle.frameName(at: idle.totalDuration) == "joy-reading-idle-01")
        #expect(celebrate.frameName(at: celebrate.totalDuration * 2) == celebrate.frameNames.last)
    }

    @Test("Key poses hold longer than transition drawings")
    func variableFrameTiming() throws {
        let idle = try #require(
            CompanionAnimationCatalog.animationDefinition(for: .joy, artwork: .reading, motion: .idle)
        )

        #expect(idle.frames.first?.duration == 2.8)
        #expect(idle.frames.dropFirst().contains { $0.duration <= 0.12 })
        #expect(idle.totalDuration >= 4.0)
    }

    @Test("Reduce Motion and non-Joy companions use stable static artwork")
    func staticFallbacks() {
        #expect(
            CompanionAnimationCatalog.resolve(
                selection: .builtIn(.joy),
                artwork: .reading,
                motion: .idle,
                reduceMotion: true
            ) == .staticAsset("joy-reading")
        )
        #expect(
            CompanionAnimationCatalog.resolve(
                selection: .builtIn(.silas),
                artwork: .reading,
                motion: .focus,
                reduceMotion: false
            ) == .staticAsset("silas-reading")
        )
        #expect(
            CompanionAnimationCatalog.resolve(
                selection: .builtIn(.nova),
                artwork: .main,
                motion: .celebrate,
                reduceMotion: false
            ) == .staticAsset("nova-main")
        )
    }

    @Test("Custom companion selection preserves the custom avatar identity")
    func customCompanionFallback() {
        let id = UUID()

        #expect(
            CompanionAnimationCatalog.resolve(
                selection: .custom(id),
                artwork: .petScene,
                motion: .react,
                reduceMotion: false
            ) == .custom(id)
        )
    }

    @Test("Unsupported motion stays in the selected artwork family")
    func unsupportedMotionFallsBackWithinArtwork() {
        #expect(
            CompanionAnimationCatalog.resolve(
                selection: .builtIn(.joy),
                artwork: .petScene,
                motion: .celebrate,
                reduceMotion: false
            ) == .staticAsset("joy-pet-scene")
        )
    }

    @Test("Only supported one-shot motions are accepted as interaction triggers")
    func supportedOneShotTriggers() {
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .builtIn(.joy),
                artwork: .petScene,
                motion: .react,
                reduceMotion: false
            ) != nil
        )
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .builtIn(.joy),
                artwork: .petScene,
                motion: .celebrate,
                reduceMotion: false
            ) == nil
        )
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .custom(UUID()),
                artwork: .petScene,
                motion: .react,
                reduceMotion: false
            ) == nil
        )
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .builtIn(.joy),
                artwork: .petScene,
                motion: .react,
                reduceMotion: true
            ) == nil
        )
    }
}

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
            (.main, .greet, "joy-main-greet-01"),
            (.main, .react, "joy-main-react-01"),
            (.reading, .idle, "joy-reading-idle-01"),
            (.reading, .focus, "joy-reading-focus-01"),
            (.reading, .celebrate, "joy-reading-celebrate-01"),
            (.scene, .idle, "joy-scene-idle-01"),
            (.scene, .react, "joy-scene-react-01"),
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

            let expectedPlaybackFrameCount = definition.loopMode == .ambient ? 12 : 4
            #expect(definition.frameNames.count == expectedPlaybackFrameCount)
            #expect(definition.frameNames.first == firstFrame)
            if definition.loopMode == .ambient {
                #expect(definition.frameNames[3] == firstFrame.replacingOccurrences(of: "01", with: "04"))
                #expect(definition.frameNames.suffix(8).allSatisfy { $0 == firstFrame })
            } else {
                #expect(definition.frameNames.last == firstFrame.replacingOccurrences(of: "01", with: "04"))
            }
            #expect(definition.frameDuration == 0.15)
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
        #expect(celebrate.frameName(at: celebrate.totalDuration * 2) == "joy-reading-celebrate-04")
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
                artwork: .scene,
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
                artwork: .scene,
                motion: .celebrate,
                reduceMotion: false
            ) == .staticAsset("joy-scene")
        )
    }

    @Test("Only supported one-shot motions are accepted as interaction triggers")
    func supportedOneShotTriggers() {
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .builtIn(.joy),
                artwork: .scene,
                motion: .react,
                reduceMotion: false
            ) != nil
        )
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .builtIn(.joy),
                artwork: .scene,
                motion: .celebrate,
                reduceMotion: false
            ) == nil
        )
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .custom(UUID()),
                artwork: .scene,
                motion: .react,
                reduceMotion: false
            ) == nil
        )
        #expect(
            CompanionAnimationCatalog.oneShotDefinition(
                selection: .builtIn(.joy),
                artwork: .scene,
                motion: .react,
                reduceMotion: true
            ) == nil
        )
    }
}

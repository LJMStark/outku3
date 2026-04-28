import Testing
import Foundation
@testable import KiroleFeature

// MARK: - Pet Asset Coverage Tests
//
// Verifies that every image name referenced in code actually has a corresponding
// imageset in Media.xcassets. Uses the process working directory (always the
// package root when running `swift test`) to locate the source tree.

@Suite("Pet Asset Coverage")
struct PetAssetCoverageTests {

    // `swift test` always runs with cwd = package root, so this path is stable.
    private static let xcassetsURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/KiroleFeature/Resources/Media.xcassets")

    private func imagesetExists(_ name: String) -> Bool {
        let url = Self.xcassetsURL.appendingPathComponent("\(name).imageset")
        return FileManager.default.fileExists(atPath: url.path)
    }

    @Test("All PetForm image names have matching imagesets")
    func petFormImagesets() {
        for form in PetForm.allCases {
            #expect(
                imagesetExists(form.imageName),
                "Missing imageset for PetForm.\(form.rawValue): \(form.imageName).imageset"
            )
        }
    }

    @Test("All CompanionCharacter hero asset variants have matching imagesets")
    func companionHeroImagesets() {
        for character in CompanionCharacter.allCases {
            for variant in [CompanionCharacter.HeroAssetVariant.main, .head] {
                let name = character.heroAssetName(variant: variant)
                #expect(
                    imagesetExists(name),
                    "Missing imageset for \(character.rawValue) \(variant): \(name).imageset"
                )
            }
        }
    }

    @Test("Static tiko image assets exist")
    func staticTikoImagesets() {
        let required = ["tiko_avatar", "tiko_head", "tiko_reading", "tiko_sunrise", "tiko_sunset"]
        for name in required {
            #expect(imagesetExists(name), "Missing static imageset: \(name).imageset")
        }
    }
}

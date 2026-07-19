import Testing
@testable import KiroleFeature

@Suite("Asset Naming")
struct AssetNamingTests {
    @Test("Pet page artwork uses an explicit pet-scene suffix")
    func petSceneHeroAssetNames() {
        #expect(CompanionCharacter.joy.heroAssetName(variant: .petScene) == "joy-pet-scene")
        #expect(CompanionCharacter.silas.heroAssetName(variant: .petScene) == "silas-pet-scene")
        #expect(CompanionCharacter.nova.heroAssetName(variant: .petScene) == "nova-pet-scene")
    }

    @Test("Hardware display scene previews use their own asset namespace")
    func displayScenePreviewAssetNames() {
        #expect(DisplayScene.harbor.previewAssetName == "display-scene-preview-harbor")
        #expect(DisplayScene.forest.previewAssetName == "display-scene-preview-forest")
        #expect(DisplayScene.nightCity.previewAssetName == "display-scene-preview-night-city")
    }
}

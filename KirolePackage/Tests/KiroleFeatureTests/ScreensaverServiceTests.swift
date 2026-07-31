import Testing
@testable import KiroleFeature

@Suite("Screensaver delivery")
@MainActor
struct ScreensaverServiceTests {
    @Test("sleep response uses an immediate fallback and caches AI text for the next sleep")
    func sleepResponseDoesNotWaitForAI() async {
        let generator = ScreensaverQuoteGeneratorSpy(result: "A cached note from Joy.")
        let service = ScreensaverService(quoteGenerator: generator)

        let immediate = service.getScreensaverConfig(
            usageDays: 2,
            currentSceneId: "harbor",
            userProfile: .default,
            topTaskTitles: ["Ship the focus transaction"],
            upcomingEventTitles: [],
            customCompanion: nil
        )

        #expect(immediate.quote == ScreensaverService.fallbackQuote)

        await service.waitForPendingGeneration()

        let cached = service.getScreensaverConfig(
            usageDays: 2,
            currentSceneId: "harbor",
            userProfile: .default,
            topTaskTitles: ["Ship the focus transaction"],
            upcomingEventTitles: [],
            customCompanion: nil
        )

        #expect(cached.quote == "A cached note from Joy.")
        #expect(await generator.requestCount == 1)
    }
}

private actor ScreensaverQuoteGeneratorSpy: ScreensaverQuoteGenerating {
    private(set) var requestCount = 0
    private let result: String

    init(result: String) {
        self.result = result
    }

    func isConfiguredForScreensaverQuote() -> Bool {
        true
    }

    func generateScreensaverQuote(
        isPostcard: Bool,
        usageDays: Int,
        workContext: String,
        profileContext: String
    ) async throws -> String {
        requestCount += 1
        return result
    }
}

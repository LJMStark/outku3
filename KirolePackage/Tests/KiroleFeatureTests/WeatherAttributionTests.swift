import Foundation
import Testing
@testable import KiroleFeature

@Suite("Apple Weather attribution")
struct WeatherAttributionTests {
    @Test("Weather attribution marks stay out of the existing Codable shape")
    func attributionMarksStayRuntimeOnly() throws {
        let weather = Weather(
            hasData: true,
            attributionLegalURLString: "https://weather.example/legal",
            attributionCombinedMarkLightURLString: "https://weather.example/light.svg",
            attributionServiceName: "Weather"
        )

        let data = try JSONEncoder().encode(weather)
        let decoded = try JSONDecoder().decode(Weather.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        #expect(decoded.attributionLegalURLString == "https://weather.example/legal")
        #expect(!json.contains("attributionCombinedMarkLightURLString"))
        #expect(!json.contains("attributionServiceName"))
        #expect(decoded.attributionCombinedMarkLightURLString == nil)
        #expect(decoded.attributionServiceName == "Weather")
    }

    @Test("Older Weather payloads keep a safe attribution fallback")
    func legacyPayloadUsesFallbackAttribution() throws {
        let weather = try JSONDecoder().decode(Weather.self, from: Data("{}".utf8))

        #expect(weather.attributionLegalURLString == Weather.appleWeatherLegalURLString)
        #expect(weather.attributionCombinedMarkLightURLString == nil)
        #expect(weather.attributionServiceName == "Weather")
    }

    @Test("Home places a subtle official mark after Today instead of inside the header")
    func homeUsesOfficialMarkAfterToday() throws {
        let header = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Components/AppHeaderView.swift"
        )
        let home = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Home/HomeView.swift"
        )
        let settings = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsView.swift"
        )
        let mark = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Components/AppleWeatherAttributionMark.swift"
        )
        let service = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Core/Services/WeatherService.swift"
        )

        #expect(!header.contains("\\u{F8FF} Weather"))
        #expect(!settings.contains("\\u{F8FF} Weather"))
        #expect(!header.contains("AppleWeatherAttributionMark"))
        #expect(!header.contains("Home_WeatherAttribution"))
        #expect(settings.contains("AppleWeatherAttributionMark"))
        #expect(settings.contains("attributionCombinedMarkLightURLString"))
        #expect(mark.contains("AsyncImage"))
        #expect(mark.contains("struct AppleWeatherAttributionFooter"))
        #expect(mark.contains("Weather Data Sources"))
        #expect(mark.contains("height: 10"))
        #expect(mark.contains("Home_WeatherAttribution"))
        #expect(service.contains("combinedMarkLightURL"))
        #expect(!service.contains("squareMarkURL"))
        #expect(!service.contains("combinedMarkDarkURL"))

        let today = try #require(
            home.range(of: "DaySectionView(date: dataSource.dateForOffset(0), showPet: true)")
        )
        let attribution = try #require(home.range(of: "AppleWeatherAttributionFooter()"))
        let remainingDays = try #require(
            home.range(of: "ForEach(dataSource.dayOffsets.dropFirst(), id: \\.self)")
        )
        #expect(today.lowerBound < attribution.lowerBound)
        #expect(attribution.lowerBound < remainingDays.lowerBound)
    }

    private func sourceFile(path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: path),
            encoding: .utf8
        )
    }
}

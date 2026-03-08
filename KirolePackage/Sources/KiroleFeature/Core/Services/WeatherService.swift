#if os(iOS)
import Foundation
import WeatherKit
import CoreLocation

@MainActor
public final class WeatherService: NSObject {
    public static let shared = WeatherService()

    private let weatherService = WeatherKit.WeatherService.shared
    private let locationManager = CLLocationManager()

    private var cachedWeather: Weather?
    private var lastFetchDate: Date?
    private static let cacheInterval: TimeInterval = 15 * 60

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    // Prevents concurrent fetchWeather() calls from overwriting the single locationContinuation slot.
    private var isFetchingWeather = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func fetchWeather() async -> Weather {
        if isFetchingWeather {
            return cachedWeather ?? Weather()
        }

        if let cached = cachedWeather,
           let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < Self.cacheInterval {
            return cached
        }

        isFetchingWeather = true
        defer { isFetchingWeather = false }

        guard let location = await requestLocation() else {
            return cachedWeather ?? Weather()
        }

        do {
            let appleWeather = try await weatherService.weather(for: location)
            let current = appleWeather.currentWeather
            let dailyForecast = appleWeather.dailyForecast.first

            let weather = Weather(
                temperature: Int(current.temperature.converted(to: .fahrenheit).value),
                highTemp: dailyForecast.map { Int($0.highTemperature.converted(to: .fahrenheit).value) } ?? 0,
                lowTemp: dailyForecast.map { Int($0.lowTemperature.converted(to: .fahrenheit).value) } ?? 0,
                condition: mapCondition(current.condition),
                location: await reverseGeocode(location)
            )

            cachedWeather = weather
            lastFetchDate = Date()
            return weather
        } catch {
            #if DEBUG
            print("[WeatherService] fetch failed: \(error.localizedDescription)")
            #endif
            return cachedWeather ?? Weather()
        }
    }

    private func requestLocation() async -> CLLocation? {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            try? await Task.sleep(for: .milliseconds(500))
        }

        let updatedStatus = locationManager.authorizationStatus
        guard updatedStatus == .authorizedWhenInUse || updatedStatus == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.locality ?? placemarks.first?.administrativeArea ?? "Unknown"
        } catch {
            return "Unknown"
        }
    }

    private func mapCondition(_ condition: WeatherKit.WeatherCondition) -> WeatherCondition {
        switch condition {
        case .clear, .mostlyClear, .hot:
            return .sunny
        case .partlyCloudy, .mostlyCloudy:
            return .partlyCloudy
        case .cloudy, .foggy, .haze, .smoky:
            return .cloudy
        case .rain, .heavyRain, .drizzle, .freezingRain:
            return .rainy
        case .snow, .heavySnow, .sleet, .flurries, .freezingDrizzle, .blizzard:
            return .snowy
        case .thunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            return .stormy
        default:
            return .sunny
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            print("[WeatherService] location failed: \(error.localizedDescription)")
            #endif
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
#endif

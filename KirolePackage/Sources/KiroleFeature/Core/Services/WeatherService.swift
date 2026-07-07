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
            // 诊断：定位授权正常但仍拿不到坐标，vs 权限被拒——用 authStatus 区分。
            Log.weather.error("fetchWeather: no location (authStatus=\(Self.describe(self.locationManager.authorizationStatus), privacy: .public)); returning placeholder, hasData=false")
            return cachedWeather ?? Weather()
        }

        do {
            let appleWeather = try await weatherService.weather(for: location)
            let current = appleWeather.currentWeather
            let dailyForecast = appleWeather.dailyForecast.first

            // BLE protocol (docs/BLE通信协议规格文档.md §4.5) defines Weather temperature
            // as a signed int8 in *Celsius*. The App is the source of truth for that byte,
            // so store Celsius — sending Fahrenheit made the firmware misread the value
            // (e.g. 22°C shipped as 72 and rendered as 72°C). Also matches the home header's
            // bare "°" display for the China-first audience.
            let weather = Weather(
                temperature: Int(current.temperature.converted(to: .celsius).value),
                highTemp: dailyForecast.map { Int($0.highTemperature.converted(to: .celsius).value) } ?? 0,
                lowTemp: dailyForecast.map { Int($0.lowTemperature.converted(to: .celsius).value) } ?? 0,
                condition: mapCondition(current.condition),
                location: await reverseGeocode(location),
                hasData: true
            )

            cachedWeather = weather
            lastFetchDate = Date()
            Log.weather.info("fetchWeather: ok (\(weather.temperature, privacy: .public)°C \(weather.condition.rawValue, privacy: .public) H\(weather.highTemp, privacy: .public)/L\(weather.lowTemp, privacy: .public) @ \(weather.location, privacy: .public))")
            return weather
        } catch {
            // 诊断：这是 hasData=false 的头号原因。WeatherKit 授权失败（App ID/profile/JWT 时间）
            // 会抛特定 domain+code（如 WDSJWTAuthenticator… code 2）——Release 也要可见，否则全程静默。
            let ns = error as NSError
            Log.weather.error("fetchWeather: WeatherKit failed domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) desc=\(error.localizedDescription, privacy: .public)")
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

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown(\(status.rawValue))"
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
            // 诊断：权限已授予但 requestLocation 仍失败（无 fix / 定位服务关 / 超时）——区分于授权层问题。
            let ns = error as NSError
            Log.weather.error("location failed domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) desc=\(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[WeatherService] location failed: \(error.localizedDescription)")
            #endif
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
#endif

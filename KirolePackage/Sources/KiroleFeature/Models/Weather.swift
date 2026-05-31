import Foundation

public struct Weather: Sendable, Codable {
    public var temperature: Int
    public var highTemp: Int
    public var lowTemp: Int
    public var condition: WeatherCondition
    public var location: String
    /// True only when populated from a successful WeatherKit fetch.
    /// Drives whether the home header renders the weather chip + Apple Weather attribution (Guideline 5.2.5).
    public var hasData: Bool

    public init(
        temperature: Int = 22,
        highTemp: Int = 26,
        lowTemp: Int = 18,
        condition: WeatherCondition = .sunny,
        location: String = "San Francisco",
        hasData: Bool = false
    ) {
        self.temperature = temperature
        self.highTemp = highTemp
        self.lowTemp = lowTemp
        self.condition = condition
        self.location = location
        self.hasData = hasData
    }

    private enum CodingKeys: String, CodingKey {
        case temperature, highTemp, lowTemp, condition, location, hasData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.temperature = try c.decodeIfPresent(Int.self, forKey: .temperature) ?? 22
        self.highTemp = try c.decodeIfPresent(Int.self, forKey: .highTemp) ?? 26
        self.lowTemp = try c.decodeIfPresent(Int.self, forKey: .lowTemp) ?? 18
        self.condition = try c.decodeIfPresent(WeatherCondition.self, forKey: .condition) ?? .sunny
        self.location = try c.decodeIfPresent(String.self, forKey: .location) ?? "San Francisco"
        self.hasData = try c.decodeIfPresent(Bool.self, forKey: .hasData) ?? false
    }
}

public enum WeatherCondition: String, Sendable, Codable {
    case sunny = "sun.max.fill"
    case cloudy = "cloud.fill"
    case partlyCloudy = "cloud.sun.fill"
    case rainy = "cloud.rain.fill"
    case snowy = "cloud.snow.fill"
    case stormy = "cloud.bolt.fill"
}

public struct SunTimes: Sendable, Codable {
    public var sunrise: Date
    public var sunset: Date

    public init(sunrise: Date, sunset: Date) {
        self.sunrise = sunrise
        self.sunset = sunset
    }

    public static var `default`: SunTimes {
        forDate(Date())
    }

    public static func forDate(_ date: Date) -> SunTimes {
        let calendar = Calendar.current
        let sunrise = calendar.date(bySettingHour: 6, minute: 45, second: 0, of: date) ?? date
        let sunset = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: date) ?? date
        return SunTimes(sunrise: sunrise, sunset: sunset)
    }
}

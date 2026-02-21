import Foundation

public struct Weather: Sendable, Codable {
    public var temperature: Int
    public var highTemp: Int
    public var lowTemp: Int
    public var condition: WeatherCondition
    public var location: String

    public init(
        temperature: Int = 22,
        highTemp: Int = 85,
        lowTemp: Int = 64,
        condition: WeatherCondition = .sunny,
        location: String = "San Francisco"
    ) {
        self.temperature = temperature
        self.highTemp = highTemp
        self.lowTemp = lowTemp
        self.condition = condition
        self.location = location
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
        let calendar = Calendar.current
        let today = Date()
        let sunrise = calendar.date(bySettingHour: 6, minute: 45, second: 0, of: today) ?? today
        let sunset = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: today) ?? today
        return SunTimes(sunrise: sunrise, sunset: sunset)
    }
}

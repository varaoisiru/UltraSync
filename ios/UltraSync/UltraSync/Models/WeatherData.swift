import Foundation

/// Location block shared by the weather/space payloads — matches
/// GET /api/status and service.location() on the Python side.
struct PlaceInfo: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var city: String?
    var country: String?
    var timezone: String?
}

/// Weather payload mirroring GET /api/weather (service.get_weather).
/// Temperatures arrive already converted to `units` by whoever built the
/// payload — the Python service server-side, the Open-Meteo mapper here.
struct WeatherData: Codable, Equatable {
    var ok: Bool
    var location: PlaceInfo
    var units: String            // "metric" | "imperial"
    var unitSymbol: String       // "°C" | "°F"
    var current: CurrentConditions
    var hourly: [HourPoint]
    var daily: [DayForecast]
    var stale: Bool?
    var fetchedAt: String?

    enum CodingKeys: String, CodingKey {
        case ok, location, units, current, hourly, daily, stale
        case unitSymbol = "unit_symbol"
        case fetchedAt = "fetched_at"
    }

    struct CurrentConditions: Codable, Equatable {
        var temperature: Double?
        var feelsLike: Double?
        var humidity: Double?
        var precipitation: Double?
        var weatherCode: Int?
        var description: String
        var icon: String
        var cloudCover: Double?
        var windSpeed: Double?
        var windDirectionDeg: Double?
        var windDirection: String
        var isDay: Int?

        enum CodingKeys: String, CodingKey {
            case temperature, humidity, precipitation, description, icon
            case feelsLike = "feels_like"
            case weatherCode = "weather_code"
            case cloudCover = "cloud_cover"
            case windSpeed = "wind_speed"
            case windDirectionDeg = "wind_direction_deg"
            case windDirection = "wind_direction"
            case isDay = "is_day"
        }
    }

    struct HourPoint: Codable, Equatable, Identifiable {
        var time: String
        var label: String
        var temperature: Double?
        var weatherCode: Int?
        var icon: String
        var id: String { time }

        enum CodingKeys: String, CodingKey {
            case time, label, temperature, icon
            case weatherCode = "weather_code"
        }
    }

    struct DayForecast: Codable, Equatable, Identifiable {
        var date: String
        var label: String
        var max: Double?
        var min: Double?
        var weatherCode: Int?
        var icon: String
        var precipProbability: Double?
        var sunrise: String?
        var sunset: String?
        var id: String { date }

        enum CodingKeys: String, CodingKey {
            case date, label, max, min, icon, sunrise, sunset
            case weatherCode = "weather_code"
            case precipProbability = "precip_probability"
        }
    }
}

// MARK: - Open-Meteo wire format (standalone mode)

/// Raw Open-Meteo forecast response — the same request the Python
/// weather.py issues (current + hourly + daily, timezone=auto).
struct OpenMeteoResponse: Decodable {
    var latitude: Double
    var longitude: Double
    var timezone: String?
    var current: Current?
    var hourly: Hourly?
    var daily: Daily?

    struct Current: Decodable {
        var temperature2m: Double?
        var relativeHumidity2m: Double?
        var apparentTemperature: Double?
        var precipitation: Double?
        var weatherCode: Int?
        var cloudCover: Double?
        var windSpeed10m: Double?
        var windDirection10m: Double?
        var isDay: Int?
        enum CodingKeys: String, CodingKey {
            case precipitation
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case cloudCover = "cloud_cover"
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case isDay = "is_day"
        }
    }

    struct Hourly: Decodable {
        var time: [String]
        var temperature2m: [Double?]
        var weatherCode: [Int?]?
        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    struct Daily: Decodable {
        var time: [String]
        var weatherCode: [Int?]?
        var temperature2mMax: [Double?]
        var temperature2mMin: [Double?]
        var sunrise: [String]?
        var sunset: [String]?
        var precipitationProbabilityMax: [Double?]?
        enum CodingKeys: String, CodingKey {
            case time, sunrise, sunset
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }
}

/// WMO weather-code tables, ported from ultrasync/weather.py.
enum WeatherCodes {
    static func icon(_ code: Int?) -> String {
        guard let code else { return "?" }
        switch code {
        case 0: return "☀"
        case 1: return "🌤"
        case 2: return "⛅"
        case 3: return "☁"
        case 45, 48: return "🌫"
        case 51, 53, 55, 61, 63, 80, 81: return "🌧"
        case 65, 82, 95, 96, 99: return "⛈"
        case 71, 73, 75, 77, 85, 86: return "❄"
        default: return "?"
        }
    }

    static func description(_ code: Int?) -> String {
        guard let code else { return "Unknown" }
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45: return "Foggy"
        case 48: return "Icy Fog"
        case 51: return "Lt Drizzle"
        case 53: return "Drizzle"
        case 55: return "Hvy Drizzle"
        case 61: return "Lt Rain"
        case 63: return "Rain"
        case 65: return "Hvy Rain"
        case 71: return "Lt Snow"
        case 73: return "Snow"
        case 75: return "Hvy Snow"
        case 77: return "Snow Grains"
        case 80: return "Showers"
        case 81: return "Hvy Showers"
        case 82: return "Violent Showers"
        case 85: return "Snow Showers"
        case 86: return "Hvy Snow Showers"
        case 95: return "T-Storm"
        case 96, 99: return "T-Storm+Hail"
        default: return "Unknown"
        }
    }

    static func windCompass(_ degrees: Double?) -> String {
        guard let degrees else { return "?" }
        let dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let idx = Int((degrees / 22.5).rounded()) % 16
        return dirs[idx]
    }

    /// Celsius → display value in the active unit system (weather.py
    /// convert_temp).
    static func convert(_ celsius: Double?, imperial: Bool) -> Double? {
        guard let celsius else { return nil }
        return imperial ? celsius * 9 / 5 + 32 : celsius
    }
}

import Foundation

/// Space payload mirroring GET /api/space (space.py fetch_space, wrapped
/// by service.get_space with ok + location).
struct SpaceData: Codable, Equatable {
    var ok: Bool?
    var location: PlaceInfo?
    var sunTimes: SunTimes
    var moon: MoonData
    var planets: [PlanetPosition]
    var iss: ISSPosition?
    var issPasses: ISSPassInfo?

    enum CodingKeys: String, CodingKey {
        case ok, location, planets, iss
        case sunTimes = "sun_times"
        case moon = "moon_data"
        case issPasses = "iss_passes"
    }

    struct SunTimes: Codable, Equatable {
        var sunrise: String?
        var sunset: String?
        var moonrise: String?
        var moonset: String?
        var sunriseUTC: String?
        var sunsetUTC: String?

        enum CodingKeys: String, CodingKey {
            case sunrise, sunset, moonrise, moonset
            case sunriseUTC = "sunrise_utc"
            case sunsetUTC = "sunset_utc"
        }

    }

    struct MoonData: Codable, Equatable {
        var phase: Double          // 0 = new, 0.5 = full (synodic fraction)
        var illumination: Double   // percent, 0–100
        var name: String
        var icon: String

    }

    struct PlanetPosition: Codable, Equatable, Identifiable {
        var name: String
        var altitude: Double       // degrees above horizon
        var azimuth: Double        // degrees, 0 = N
        var visible: Bool
        var id: String { name }
    }

    struct ISSPassInfo: Codable, Equatable {
        var time: String
        var duration: String
        var maxElevation: String
        var brightness: String

        enum CodingKeys: String, CodingKey {
            case time, duration, brightness
            case maxElevation = "max_elevation"
        }
    }
}

/// Live ISS position — wheretheiss.at satellite 25544, shaped like the
/// Python payload's `iss` block.
struct ISSPosition: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var altitudeKm: Double
    var velocityKmh: Double
    var visibility: String?
    var live: Bool?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, visibility, live
        case altitudeKm = "altitude_km"
        case velocityKmh = "velocity_kmh"
    }
}

/// wheretheiss.at wire format (standalone mode decodes this directly).
struct ISSWireResponse: Decodable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var velocity: Double
    var visibility: String?

    func toPosition() -> ISSPosition {
        ISSPosition(latitude: (latitude * 100).rounded() / 100,
                    longitude: (longitude * 100).rounded() / 100,
                    altitudeKm: (altitude * 10).rounded() / 10,
                    velocityKmh: velocity.rounded(),
                    visibility: visibility,
                    live: true)
    }
}

// Memberwise-style initializers live in an extension so the Codable
// synthesis in the main declarations stays untouched.
extension SpaceData {
    init(ok: Bool?, location: PlaceInfo?, sunTimes: SunTimes, moon: MoonData,
         planets: [PlanetPosition], iss: ISSPosition?, issPasses: ISSPassInfo?) {
        self.ok = ok
        self.location = location
        self.sunTimes = sunTimes
        self.moon = moon
        self.planets = planets
        self.iss = iss
        self.issPasses = issPasses
    }
}

extension SpaceData.SunTimes {
    init(sunrise: String? = nil, sunset: String? = nil,
         moonrise: String? = nil, moonset: String? = nil,
         sunriseUTC: String? = nil, sunsetUTC: String? = nil) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.moonrise = moonrise
        self.moonset = moonset
        self.sunriseUTC = sunriseUTC
        self.sunsetUTC = sunsetUTC
    }
}

extension SpaceData.MoonData {
    init(phase: Double, illumination: Double, name: String, icon: String) {
        self.phase = phase
        self.illumination = illumination
        self.name = name
        self.icon = icon
    }
}

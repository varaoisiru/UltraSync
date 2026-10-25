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
        var sunrise: String? = nil
        var sunset: String? = nil
        var moonrise: String? = nil
        var moonset: String? = nil
        var sunriseUTC: String? = nil
        var sunsetUTC: String? = nil

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

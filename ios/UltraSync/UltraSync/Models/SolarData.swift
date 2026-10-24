import Foundation

/// Solar payload mirroring GET /api/solar (solar.py fetch_solar, wrapped
/// by service.get_solar with ok + cache metadata).
struct SolarData: Codable, Equatable {
    var ok: Bool?
    var sunspotNumber: Double?
    var solarFlux: Double?
    var solarWind: SolarWind?
    var geomagnetic: Geomagnetic?
    var activeRegions: Int?
    var alerts: [String]
    var forecast: [String: KpForecastDay]
    var stale: Bool?

    enum CodingKeys: String, CodingKey {
        case ok, alerts, forecast, stale
        case sunspotNumber = "sunspot_number"
        case solarFlux = "solar_flux"
        case solarWind = "solar_wind"
        case geomagnetic
        case activeRegions = "active_regions"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
        sunspotNumber = try c.decodeIfPresent(Double.self, forKey: .sunspotNumber)
        solarFlux = try c.decodeIfPresent(Double.self, forKey: .solarFlux)
        solarWind = try c.decodeIfPresent(SolarWind.self, forKey: .solarWind)
        geomagnetic = try c.decodeIfPresent(Geomagnetic.self, forKey: .geomagnetic)
        activeRegions = try c.decodeIfPresent(Int.self, forKey: .activeRegions)
        alerts = try c.decodeIfPresent([String].self, forKey: .alerts) ?? []
        forecast = try c.decodeIfPresent([String: KpForecastDay].self, forKey: .forecast) ?? [:]
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale)
    }

    init(ok: Bool?, sunspotNumber: Double?, solarFlux: Double?,
         solarWind: SolarWind?, geomagnetic: Geomagnetic?,
         activeRegions: Int?, alerts: [String],
         forecast: [String: KpForecastDay], stale: Bool?) {
        self.ok = ok
        self.sunspotNumber = sunspotNumber
        self.solarFlux = solarFlux
        self.solarWind = solarWind
        self.geomagnetic = geomagnetic
        self.activeRegions = activeRegions
        self.alerts = alerts
        self.forecast = forecast
        self.stale = stale
    }

    struct SolarWind: Codable, Equatable {
        var speed: Double?        // km/s, proton_speed
        var density: Double?      // p/cm³
        var temperature: Double?  // K
        var bz: Double?           // nT, GSM
        var bt: Double?           // nT
    }

    struct Geomagnetic: Codable, Equatable {
        var kpIndex: Double
        var aIndex: Double
        var label: String
        var auroraProbability: Int

        enum CodingKeys: String, CodingKey {
            case label
            case kpIndex = "kp_index"
            case aIndex = "a_index"
            case auroraProbability = "aurora_probability"
        }
    }

    struct KpForecastDay: Codable, Equatable {
        var kpIndex: Double?
        var aIndex: Double?
        enum CodingKeys: String, CodingKey {
            case kpIndex = "kp_index"
            case aIndex = "a_index"
        }
    }

    /// Forecast rows in date order for the bar chart.
    var forecastSorted: [(date: String, day: KpForecastDay)] {
        forecast.sorted { $0.key < $1.key }.map { (date: $0.key, day: $0.value) }
    }
}

/// Kp label + aurora rule, ported from solar.py kp_label /
/// aurora_probability (used when assembling standalone data).
enum SolarRules {
    static func kpLabel(_ kp: Double?) -> String {
        guard let kp else { return "Unknown" }
        switch kp {
        case ..<4: return "Quiet"
        case ..<5: return "Unsettled"
        case ..<6: return "G1 Minor storm"
        case ..<7: return "G2 Moderate storm"
        case ..<8: return "G3 Strong storm"
        case ..<9: return "G4 Severe storm"
        default: return "G5 Extreme storm"
        }
    }

    static func auroraProbability(_ kp: Double?) -> Int {
        guard let kp else { return 0 }
        return min(100, Int(kp * 11))
    }
}

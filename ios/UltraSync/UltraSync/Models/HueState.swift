import Foundation

/// Hue payload mirroring GET /api/hue/status (api.py HueManager.status).
/// Credentials are never part of this payload — only the apiKeySet flag,
/// exactly like the Python API.
struct HueState: Codable, Equatable {
    var configured: Bool
    var bridgeIP: String?
    var apiKeySet: Bool
    var lights: [HueLight]
    var configuredLightIDs: [Int]
    var syncConditions: Bool
    var fx: HueFXStatus?

    enum CodingKeys: String, CodingKey {
        case configured, lights, fx
        case bridgeIP = "bridge_ip"
        case apiKeySet = "api_key_set"
        case configuredLightIDs = "configured_light_ids"
        case syncConditions = "sync_conditions"
    }

    static let unconfigured = HueState(configured: false, bridgeIP: nil,
                                       apiKeySet: false, lights: [],
                                       configuredLightIDs: [],
                                       syncConditions: false, fx: nil)
}

struct HueLight: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    var on: Bool
    var bri: Int?        // 1–254
    var hue: Int?        // 0–65535
    var sat: Int?        // 0–254
    var reachable: Bool

    init(id: Int, name: String, on: Bool, bri: Int?, hue: Int?, sat: Int?, reachable: Bool) {
        self.id = id
        self.name = name
        self.on = on
        self.bri = bri
        self.hue = hue
        self.sat = sat
        self.reachable = reachable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Light \(id)"
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        bri = try c.decodeIfPresent(Int.self, forKey: .bri)
        hue = try c.decodeIfPresent(Int.self, forKey: .hue)
        sat = try c.decodeIfPresent(Int.self, forKey: .sat)
        reachable = try c.decodeIfPresent(Bool.self, forKey: .reachable) ?? true
    }

    var brightnessFraction: Double {
        get { Double(bri ?? 0) / 254.0 }
        set { bri = max(1, min(254, Int(newValue * 254))) }
    }
}

struct HueFXStatus: Codable, Equatable {
    var playing: HueFXPlaying?
}

struct HueFXPlaying: Codable, Equatable {
    var index: Int
    var name: String
}

/// GET /api/hue/fx envelope (the 100-effect library).
struct HueFXListResponse: Codable {
    var effects: [HueFXEffect]
}

struct HueFXEffect: Codable, Equatable, Identifiable {
    var index: Int
    var id: String
    var name: String
    var description: String
    var steps: Int
}

/// Direct-bridge wire format (standalone mode): GET
/// http://{bridge}/api/{username}/lights returns an object keyed by id.
struct HueBridgeLight: Decodable {
    struct State: Decodable {
        var on: Bool
        var bri: Int?
        var hue: Int?
        var sat: Int?
        var reachable: Bool?
    }
    var state: State
    var name: String

    func toLight(id: Int) -> HueLight {
        HueLight(id: id, name: name, on: state.on, bri: state.bri,
                 hue: state.hue, sat: state.sat,
                 reachable: state.reachable ?? true)
    }
}

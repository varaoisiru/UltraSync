import Foundation
import SwiftUI

/// Per-panel load state, so every view can render loading / loaded /
/// error uniformly (the web GUI's LIVE-or-CACHED contract, natively).
enum PanelState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)

    var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }
    var errorMessage: String? {
        if case .error(let m) = self { return m }
        return nil
    }
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum DataMode: String, CaseIterable, Identifiable {
    case standalone
    case backend
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standalone: return "Standalone (direct sources)"
        case .backend: return "UltraSync Server"
        }
    }
}

/// Central store: owns settings (persisted in UserDefaults), resolves
/// location, and fans refresh calls out to APIClient for whichever data
/// mode is active. Views observe the published panel states.
@MainActor
final class DataStore: ObservableObject {
    let client = APIClient()

    // MARK: settings (persisted)

    @Published var mode: DataMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "us_mode") }
    }
    @Published var backendURLString: String {
        didSet { UserDefaults.standard.set(backendURLString, forKey: "us_backend_url") }
    }
    @Published var imperialUnits: Bool {
        didSet { UserDefaults.standard.set(imperialUnits, forKey: "us_units_imperial") }
    }
    @Published var timeFormat12h: Bool {
        didSet { UserDefaults.standard.set(timeFormat12h, forKey: "us_time_12h") }
    }
    @Published var showScanlines: Bool {
        didSet { UserDefaults.standard.set(showScanlines, forKey: "us_scanlines") }
    }
    @Published var hueBridgeIP: String {
        didSet { UserDefaults.standard.set(hueBridgeIP, forKey: "us_hue_bridge") }
    }
    @Published var hueUsername: String {
        didSet { UserDefaults.standard.set(hueUsername, forKey: "us_hue_user") }
    }

    var backendBaseURL: URL? {
        let s = backendURLString.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        return URL(string: s.hasPrefix("http") ? s : "http://" + s)
    }
    var unitsName: String { imperialUnits ? "imperial" : "metric" }
    var unitSymbol: String { imperialUnits ? "°F" : "°C" }
    var timeFormatName: String { timeFormat12h ? "12h" : "24h" }

    // MARK: state

    @Published var place: PlaceInfo
    @Published var backendVersion: String?
    @Published var newsState: PanelState<NewsResponse> = .idle
    @Published var weatherState: PanelState<WeatherData> = .idle
    @Published var solarState: PanelState<SolarData> = .idle
    @Published var spaceState: PanelState<SpaceData> = .idle
    @Published var hueState: PanelState<HueState> = .idle

    /// Standalone-mode read markers (backend mode tracks read state
    /// server-side and reports it in the payload's `viewed` flag).
    @Published private(set) var readLinks: Set<String> {
        didSet { UserDefaults.standard.set(Array(readLinks), forKey: "us_read_links") }
    }

    init() {
        let d = UserDefaults.standard
        mode = DataMode(rawValue: d.string(forKey: "us_mode") ?? "standalone") ?? .standalone
        backendURLString = d.string(forKey: "us_backend_url") ?? "http://127.0.0.1:8077"
        imperialUnits = d.bool(forKey: "us_units_imperial")
        timeFormat12h = d.bool(forKey: "us_time_12h")
        showScanlines = d.object(forKey: "us_scanlines") as? Bool ?? true
        hueBridgeIP = d.string(forKey: "us_hue_bridge") ?? ""
        hueUsername = d.string(forKey: "us_hue_user") ?? ""
        readLinks = Set(d.stringArray(forKey: "us_read_links") ?? [])
        // Same fallback coordinates the Python location module uses
        // before geolocation resolves.
        place = PlaceInfo(latitude: 40.7128, longitude: -74.0060,
                          city: nil, country: nil, timezone: nil)
    }

    // MARK: location + boot

    func boot() async {
        await resolveLocation()
        async let n: Void = refreshNews()
        async let w: Void = refreshWeather()
        async let s: Void = refreshSolar()
        async let sp: Void = refreshSpace()
        async let h: Void = refreshHue()
        _ = await (n, w, s, sp, h)
    }

    func resolveLocation() async {
        switch mode {
        case .standalone:
            if let p = try? await client.fetchIPLocation() { place = p }
        case .backend:
            if let base = backendBaseURL,
               let status = try? await client.backendStatus(base: base) {
                place = status.location
                backendVersion = status.version
            }
        }
    }

    // MARK: news

    func refreshNews() async {
        if newsState.value == nil { newsState = .loading }
        do {
            switch mode {
            case .standalone:
                let articles = await client.fetchAllFeeds()
                guard !articles.isEmpty else {
                    throw APIError.noData("No feeds reachable")
                }
                let marked = articles.map { a -> NewsArticle in
                    var a = a
                    if readLinks.contains(a.link) { a.viewed = 1 }
                    return a
                }
                let unread = marked.filter { $0.isUnread }.count
                newsState = .loaded(NewsResponse(
                    articles: marked, unread: unread, totalUnread: unread,
                    sources: FeedSource.names, count: marked.count))
            case .backend:
                guard let base = backendBaseURL else {
                    throw APIError.badURL(backendURLString)
                }
                let resp = try await client.backend(NewsResponse.self, base: base, path: "api/news")
                newsState = .loaded(resp)
            }
        } catch {
            newsState = .error(error.localizedDescription)
        }
    }

    func markRead(_ article: NewsArticle) {
        readLinks.insert(article.link)
        if case .loaded(var resp) = newsState,
           let idx = resp.articles.firstIndex(where: { $0.link == article.link }) {
            resp.articles[idx].viewed = 1
            resp.unread = resp.articles.filter { $0.isUnread }.count
            resp.totalUnread = resp.unread
            newsState = .loaded(resp)
        }
        if mode == .backend, let base = backendBaseURL {
            Task { try? await client.postJSON(to: base.appendingPathComponent("api/news/read"),
                                              body: ["link": article.link]) }
        }
    }

    func markAllRead() {
        if case .loaded(var resp) = newsState {
            for i in resp.articles.indices { resp.articles[i].viewed = 1 }
            readLinks.formUnion(resp.articles.map(\.link))
            resp.unread = 0
            resp.totalUnread = 0
            newsState = .loaded(resp)
        }
        if mode == .backend, let base = backendBaseURL {
            Task { try? await client.postJSON(to: base.appendingPathComponent("api/news/read-all"),
                                              body: [:]) }
        }
    }

    func refreshNewsFromServer() async {
        guard mode == .backend, let base = backendBaseURL else {
            await refreshNews()
            return
        }
        do {
            let resp: NewsResponse = try await {
                let data = try await client.postJSON(to: base.appendingPathComponent("api/news/refresh"), body: [:])
                return try JSONDecoder().decode(NewsResponse.self, from: data)
            }()
            newsState = .loaded(resp)
        } catch {
            await refreshNews()
        }
    }

    // MARK: weather

    func refreshWeather() async {
        if weatherState.value == nil { weatherState = .loading }
        do {
            switch mode {
            case .standalone:
                let om = try await client.fetchOpenMeteo(lat: place.latitude, lon: place.longitude)
                weatherState = .loaded(client.mapWeather(om, place: place,
                                                         imperial: imperialUnits,
                                                         timeFormat: timeFormatName))
            case .backend:
                guard let base = backendBaseURL else { throw APIError.badURL(backendURLString) }
                weatherState = .loaded(try await client.backend(WeatherData.self, base: base, path: "api/weather"))
            }
        } catch {
            weatherState = .error(error.localizedDescription)
        }
    }

    // MARK: solar

    func refreshSolar() async {
        if solarState.value == nil { solarState = .loading }
        do {
            switch mode {
            case .standalone:
                solarState = .loaded(try await client.fetchSolarStandalone())
            case .backend:
                guard let base = backendBaseURL else { throw APIError.badURL(backendURLString) }
                solarState = .loaded(try await client.backend(SolarData.self, base: base, path: "api/solar"))
            }
        } catch {
            solarState = .error(error.localizedDescription)
        }
    }

    // MARK: space

    func refreshSpace() async {
        if spaceState.value == nil { spaceState = .loading }
        do {
            switch mode {
            case .standalone:
                spaceState = .loaded(try await buildStandaloneSpace())
            case .backend:
                guard let base = backendBaseURL else { throw APIError.badURL(backendURLString) }
                spaceState = .loaded(try await client.backend(SpaceData.self, base: base, path: "api/space"))
            }
        } catch {
            spaceState = .error(error.localizedDescription)
        }
    }

    private func buildStandaloneSpace() async throws -> SpaceData {
        var times = (try? await client.fetchSpaceTimes(lat: place.latitude, lon: place.longitude))
            ?? SpaceData.SunTimes()
        if times.sunrise == nil, let st = SpaceCalculator.sunTimesUTC(on: Date(), lat: place.latitude, lon: place.longitude) {
            let f = ISO8601DateFormatter()
            times.sunriseUTC = f.string(from: st.sunrise)
            times.sunsetUTC = f.string(from: st.sunset)
        }
        let iss = try? await client.fetchISS()
        return SpaceData(
            ok: true,
            location: place,
            sunTimes: times,
            moon: SpaceCalculator.moonData(),
            planets: SpaceCalculator.planetPositions(lat: place.latitude, lon: place.longitude),
            iss: iss,
            issPasses: SpaceData.ISSPassInfo(time: "Multiple passes daily",
                                             duration: "2-5 min",
                                             maxElevation: "Varies",
                                             brightness: "-2.5 to -4.0 mag"))
    }

    /// Lightweight 30-second ISS tick used by SpaceView's timer.
    func refreshISS() async {
        guard let iss = try? await client.fetchISS(),
              case .loaded(var space) = spaceState else { return }
        space.iss = iss
        spaceState = .loaded(space)
    }

    // MARK: hue

    var hueConfiguredLocally: Bool {
        !hueBridgeIP.trimmingCharacters(in: .whitespaces).isEmpty &&
        !hueUsername.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func refreshHue() async {
        if hueState.value == nil { hueState = .loading }
        do {
            switch mode {
            case .backend:
                guard let base = backendBaseURL else { throw APIError.badURL(backendURLString) }
                hueState = .loaded(try await client.backend(HueState.self, base: base, path: "api/hue/status"))
            case .standalone:
                guard hueConfiguredLocally else {
                    hueState = .loaded(.unconfigured)
                    return
                }
                let lights = try await fetchBridgeLights()
                hueState = .loaded(HueState(
                    configured: true, bridgeIP: hueBridgeIP, apiKeySet: true,
                    lights: lights, configuredLightIDs: lights.map(\.id),
                    syncConditions: false, fx: nil))
            }
        } catch {
            hueState = .error(error.localizedDescription)
        }
    }

    private func bridgeURL(_ path: String) -> URL? {
        URL(string: "http://\(hueBridgeIP)/api/\(hueUsername)/\(path)")
    }

    func fetchBridgeLights() async throws -> [HueLight] {
        guard let url = bridgeURL("lights") else { throw APIError.badURL("bridge") }
        let dict = try await client.json([String: HueBridgeLight].self, from: url)
        return dict.compactMap { key, value in
            Int(key).map { value.toLight(id: $0) }
        }.sorted { $0.id < $1.id }
    }

    func setLight(id: Int, on: Bool? = nil, brightness: Double? = nil) async {
        var payload: [String: Any] = [:]
        if let on { payload["on"] = on }
        if let brightness { payload["bri"] = max(1, min(254, Int(brightness * 254))) }
        guard !payload.isEmpty else { return }
        do {
            switch mode {
            case .backend:
                guard let base = backendBaseURL else { return }
                payload["id"] = id
                try await client.postJSON(to: base.appendingPathComponent("api/hue/light"), body: payload)
            case .standalone:
                guard let url = bridgeURL("lights/\(id)/state") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                _ = try await client.session.data(for: req)
            }
            await refreshHue()
        } catch {
            hueState = .error(error.localizedDescription)
        }
    }

    func setAllLights(on: Bool) async {
        guard case .loaded(let state) = hueState else { return }
        for light in state.lights {
            await setLight(id: light.id, on: on)
        }
    }

    func setHueSync(enabled: Bool) async {
        guard mode == .backend, let base = backendBaseURL else { return }
        _ = try? await client.postJSON(to: base.appendingPathComponent("api/hue/sync"),
                                       body: ["enabled": enabled])
        await refreshHue()
    }

    func fetchFXList() async -> [HueFXEffect] {
        guard mode == .backend, let base = backendBaseURL else { return [] }
        let resp = try? await client.backend(HueFXListResponse.self, base: base, path: "api/hue/fx")
        return resp?.effects ?? []
    }

    func playFX(index: Int?) async {
        guard mode == .backend, let base = backendBaseURL else { return }
        let body: [String: Any] = index == nil ? ["action": "stop"] : ["index": index!]
        _ = try? await client.postJSON(to: base.appendingPathComponent("api/hue/fx"), body: body)
        await refreshHue()
    }
}

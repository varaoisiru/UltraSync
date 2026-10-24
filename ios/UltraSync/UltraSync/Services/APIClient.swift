import Foundation

enum APIError: Error, LocalizedError {
    case badURL(String)
    case http(Int)
    case network(String)
    case decoding(String)
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s): return "Bad URL: \(s)"
        case .http(let code): return "HTTP \(code)"
        case .network(let s): return s
        case .decoding(let s): return "Decode failed: \(s)"
        case .noData(let s): return s
        }
    }
}

/// All network access for the app. Two data planes:
///  - standalone: the same free sources the Python modules use
///    (Open-Meteo, NOAA SWPC, RSS feeds, wheretheiss.at, ip-api) —
///    no API keys anywhere.
///  - backend: a running UltraSync server's JSON API (api.py).
final class APIClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: generic helpers

    func data(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError.http(http.statusCode)
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    func json<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await data(from: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func jsonObject(from url: URL) async throws -> Any {
        let data = try await data(from: url)
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    func postJSON(to url: URL, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError.http(http.statusCode)
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    /// Flexible number extraction for SWPC JSON, whose products mix
    /// numbers and numeric strings (the Python fetchers accept both).
    static func num(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    // MARK: location (standalone: ip-api, like ultrasync/location.py)

    func fetchIPLocation() async throws -> PlaceInfo {
        struct IPResponse: Decodable {
            var lat: Double
            var lon: Double
            var city: String?
            var country: String?
            var timezone: String?
        }
        guard let url = URL(string: "http://ip-api.com/json/") else {
            throw APIError.badURL("ip-api")
        }
        let r = try await json(IPResponse.self, from: url)
        return PlaceInfo(latitude: r.lat, longitude: r.lon, city: r.city,
                         country: r.country, timezone: r.timezone)
    }

    // MARK: weather (standalone: Open-Meteo, the weather.py request)

    func fetchOpenMeteo(lat: Double, lon: Double) async throws -> OpenMeteoResponse {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m,precipitation_probability,weather_code,wind_speed_10m,uv_index"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_sum,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]
        guard let url = comps.url else { throw APIError.badURL("open-meteo") }
        return try await json(OpenMeteoResponse.self, from: url)
    }

    /// Map an Open-Meteo response into the shared WeatherData shape,
    /// converting temperatures into the active unit system (the role
    /// service.get_weather plays server-side).
    func mapWeather(_ om: OpenMeteoResponse, place: PlaceInfo,
                    imperial: Bool, timeFormat: String) -> WeatherData {
        let symbol = imperial ? "°F" : "°C"
        let cur = om.current
        let current = WeatherData.CurrentConditions(
            temperature: WeatherCodes.convert(cur?.temperature2m, imperial: imperial),
            feelsLike: WeatherCodes.convert(cur?.apparentTemperature, imperial: imperial),
            humidity: cur?.relativeHumidity2m,
            precipitation: cur?.precipitation,
            weatherCode: cur?.weatherCode,
            description: WeatherCodes.description(cur?.weatherCode),
            icon: WeatherCodes.icon(cur?.weatherCode),
            cloudCover: cur?.cloudCover,
            windSpeed: cur?.windSpeed10m,
            windDirectionDeg: cur?.windDirection10m,
            windDirection: WeatherCodes.windCompass(cur?.windDirection10m),
            isDay: cur?.isDay)

        var hourly: [WeatherData.HourPoint] = []
        if let h = om.hourly {
            for (i, t) in h.time.enumerated() where i < h.temperature2m.count {
                let code = (h.weatherCode?[i]) ?? nil
                hourly.append(WeatherData.HourPoint(
                    time: t,
                    label: Self.formatTime(t, timeFormat: timeFormat),
                    temperature: WeatherCodes.convert(h.temperature2m[i], imperial: imperial),
                    weatherCode: code,
                    icon: WeatherCodes.icon(code)))
            }
        }

        var daily: [WeatherData.DayForecast] = []
        if let d = om.daily {
            for (i, day) in d.time.enumerated() {
                let code = (d.weatherCode?[i]) ?? nil
                daily.append(WeatherData.DayForecast(
                    date: day,
                    label: Self.weekdayLabel(day),
                    max: WeatherCodes.convert(i < d.temperature2mMax.count ? d.temperature2mMax[i] : nil, imperial: imperial),
                    min: WeatherCodes.convert(i < d.temperature2mMin.count ? d.temperature2mMin[i] : nil, imperial: imperial),
                    weatherCode: code,
                    icon: WeatherCodes.icon(code),
                    precipProbability: (d.precipitationProbabilityMax?[i]) ?? nil,
                    sunrise: (d.sunrise?[i]) ?? nil,
                    sunset: (d.sunset?[i]) ?? nil))
            }
        }

        return WeatherData(
            ok: true,
            location: PlaceInfo(latitude: om.latitude, longitude: om.longitude,
                                city: place.city, country: place.country,
                                timezone: om.timezone ?? place.timezone),
            units: imperial ? "imperial" : "metric",
            unitSymbol: symbol,
            current: current,
            hourly: hourly,
            daily: daily,
            stale: false,
            fetchedAt: nil)
    }

    static func formatTime(_ iso: String, timeFormat: String) -> String {
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let date = inFmt.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = timeFormat == "12h" ? "h:mm a" : "HH:mm"
        return out.string(from: date)
    }

    static func weekdayLabel(_ isoDate: String) -> String {
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: String(isoDate.prefix(10))) else { return isoDate }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "EEE"
        return out.string(from: date)
    }

    // MARK: space times (standalone: Open-Meteo daily, space.py's online path)

    struct SpaceTimesWire: Decodable {
        struct Daily: Decodable {
            var sunrise: [String]?
            var sunset: [String]?
            var moonrise: [String]?
            var moonset: [String]?
        }
        var daily: Daily?
    }

    func fetchSpaceTimes(lat: Double, lon: Double) async throws -> SpaceData.SunTimes {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "daily", value: "sunrise,sunset,moonrise,moonset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = comps.url else { throw APIError.badURL("open-meteo space") }
        let wire = try await json(SpaceTimesWire.self, from: url)
        let d = wire.daily
        return SpaceData.SunTimes(
            sunrise: d?.sunrise?.first ?? nil,
            sunset: d?.sunset?.first ?? nil,
            moonrise: d?.moonrise?.first ?? nil,
            moonset: d?.moonset?.first ?? nil)
    }

    // MARK: ISS (wheretheiss.at, space.py ISS_URL)

    func fetchISS() async throws -> ISSPosition {
        guard let url = URL(string: "https://api.wheretheiss.at/v1/satellites/25544") else {
            throw APIError.badURL("iss")
        }
        let wire = try await json(ISSWireResponse.self, from: url)
        return wire.toPosition()
    }

    // MARK: solar (standalone: NOAA SWPC feeds, solar.py)

    private static let swpc = "https://services.swpc.noaa.gov"

    func fetchSolarStandalone() async throws -> SolarData {
        async let indicesObj = try? jsonObject(from: URL(string: "\(Self.swpc)/json/solar-cycle/observed-solar-cycle-indices.json")!)
        async let windObj = try? jsonObject(from: URL(string: "\(Self.swpc)/json/rtsw/rtsw_wind_1m.json")!)
        async let magObj = try? jsonObject(from: URL(string: "\(Self.swpc)/json/rtsw/rtsw_mag_1m.json")!)
        async let kpObj = try? jsonObject(from: URL(string: "\(Self.swpc)/json/planetary_k_index_1m.json")!)
        async let regionsObj = try? jsonObject(from: URL(string: "\(Self.swpc)/json/solar-region/solar-region-summary.json")!)
        async let forecastObj = try? jsonObject(from: URL(string: "\(Self.swpc)/products/noaa-planetary-k-index.json")!)

        var gotAny = false
        var sunspot: Double?
        var flux: Double?
        var wind: SolarData.SolarWind?
        var geo: SolarData.Geomagnetic?
        var regions: Int?
        var forecast: [String: SolarData.KpForecastDay] = [:]

        let indicesValue = await indicesObj
        if let rows = indicesValue as? [[String: Any]] {
            for row in rows.reversed() {
                if sunspot == nil {
                    sunspot = ["smoothed_ssn", "observed_swpc_ssn", "ssn"]
                        .compactMap { Self.num(row[$0]) }.first { $0 >= 0 }
                }
                if flux == nil {
                    flux = ["smoothed_f10.7", "f10.7"]
                        .compactMap { Self.num(row[$0]) }.first { $0 >= 0 }
                }
                if sunspot != nil && flux != nil { break }
            }
            gotAny = true
        }

        let windValue = await windObj
        if let rows = windValue as? [[String: Any]], let latest = rows.last {
            wind = SolarData.SolarWind(
                speed: Self.num(latest["proton_speed"]),
                density: Self.num(latest["proton_density"]),
                temperature: Self.num(latest["proton_temperature"]),
                bz: nil, bt: nil)
            gotAny = true
        }

        let magValue = await magObj
        if let rows = magValue as? [[String: Any]], let latest = rows.last, wind != nil {
            wind?.bz = Self.num(latest["bz_gsm"])
            wind?.bt = Self.num(latest["bt"])
        }

        let kpValue = await kpObj
        if let rows = kpValue as? [[String: Any]], let latest = rows.last {
            let kp = Self.num(latest["kp_index"]) ?? Self.num(latest["k_index"]) ?? 0
            geo = SolarData.Geomagnetic(
                kpIndex: kp,
                aIndex: Self.num(latest["a_index"]) ?? 0,
                label: SolarRules.kpLabel(kp),
                auroraProbability: SolarRules.auroraProbability(kp))
            gotAny = true
        }

        let regionsValue = await regionsObj
        if let dict = regionsValue as? [String: Any],
           let n = Self.num(dict["number_of_cmc_calculated_regions"]) {
            regions = Int(n)
            gotAny = true
        }

        let forecastValue = await forecastObj
        if let rows = forecastValue as? [Any] {
            let body: [Any]
            if let first = rows.first, first is [Any] {
                body = Array(rows.dropFirst())   // header row + array rows
            } else {
                body = rows
            }
            for entry in body {
                if let dict = entry as? [String: Any] {
                    let day = (dict["time_tag"] as? String) ?? (dict["date"] as? String) ?? ""
                    let kp = Self.num(dict["Kp"]) ?? Self.num(dict["kp_index"])
                    let a = Self.num(dict["a_running"]) ?? Self.num(dict["a_index"])
                    if !day.isEmpty, kp != nil {
                        forecast[String(day.prefix(10))] = SolarData.KpForecastDay(kpIndex: kp, aIndex: a)
                    }
                } else if let arr = entry as? [Any], arr.count >= 4,
                          let day = arr[0] as? String {
                    forecast[day] = SolarData.KpForecastDay(
                        kpIndex: Self.num(arr[2]), aIndex: Self.num(arr[3]))
                }
            }
            if !forecast.isEmpty { gotAny = true }
        }

        guard gotAny else { throw APIError.noData("All NOAA SWPC feeds unreachable") }
        return SolarData(ok: true, sunspotNumber: sunspot, solarFlux: flux,
                         solarWind: wind, geomagnetic: geo,
                         activeRegions: regions, alerts: [],
                         forecast: forecast, stale: false)
    }

    // MARK: news (standalone: RSS/Atom feeds, news.py)

    func fetchFeed(_ feed: FeedSource) async throws -> [NewsArticle] {
        guard let url = feed.url else { throw APIError.badURL(feed.urlString) }
        let data = try await data(from: url)
        return FeedService.parse(data: data, source: feed.name)
    }

    func fetchAllFeeds() async -> [NewsArticle] {
        var collected: [NewsArticle] = []
        await withTaskGroup(of: [NewsArticle].self) { group in
            for feed in FeedSource.all {
                group.addTask { (try? await self.fetchFeed(feed)) ?? [] }
            }
            for await articles in group {
                collected.append(contentsOf: articles)
            }
        }
        // Newest first, like the backend's fetched_at DESC ordering.
        return collected.sorted {
            (FeedService.parseDate($0.published) ?? .distantPast) >
            (FeedService.parseDate($1.published) ?? .distantPast)
        }
    }

    // MARK: backend mode (api.py endpoints)

    func backend<T: Decodable>(_ type: T.Type, base: URL, path: String) async throws -> T {
        try await json(T.self, from: base.appendingPathComponent(path))
    }

    func backendStatus(base: URL) async throws -> BackendStatus {
        try await backend(BackendStatus.self, base: base, path: "api/status")
    }

    func backendArticle(base: URL, link: String) async throws -> ArticleText {
        var comps = URLComponents(url: base.appendingPathComponent("api/news/article"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "link", value: link)]
        return try await json(ArticleText.self, from: comps.url!)
    }
}

/// GET /api/status shape (service.status).
struct BackendStatus: Codable {
    var ok: Bool
    var version: String
    var theme: String
    var location: PlaceInfo
    var hueConfigured: Bool
    var unread: Int

    enum CodingKeys: String, CodingKey {
        case ok, version, theme, location, unread
        case hueConfigured = "hue_configured"
    }
}

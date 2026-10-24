import SwiftUI

/// SPACE panel: rendered moon phase, sun & moon times, the computed
/// planet table, and the live ISS row (auto-refreshing every 30 s, as
/// in the GUI).
struct SpaceView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.theme
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                PanelStateView(state: store.spaceState,
                               retry: { Task { await store.refreshSpace() } }) { space in
                    ScrollView {
                        VStack(spacing: 14) {
                            moonPanel(space, theme: theme)
                            planetsPanel(space, theme: theme)
                            issPanel(space, theme: theme)
                        }
                        .padding(12)
                    }
                    .refreshable { await store.refreshSpace() }
                }
            }
            .navigationTitle("ULTRASYNC · SPACE")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if store.spaceState.value == nil { await store.refreshSpace() }
            // ISS live tick: every 30 s while the tab is on screen.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await store.refreshISS()
            }
        }
    }

    private func moonPanel(_ space: SpaceData, theme: ThemePalette) -> some View {
        let times = space.sunTimes
        return VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Sun & Moon", badge: "LIVE")
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 6) {
                    MoonDiscView(phase: space.moon.phase, size: 92)
                    Text("\(space.moon.icon) \(space.moon.name)")
                        .font(Retro.font(11, weight: .bold))
                        .foregroundColor(theme.primaryColor)
                    Text(String(format: "%.1f%% lit", space.moon.illumination))
                        .font(Retro.font(10))
                        .foregroundColor(theme.accent2Color)
                }
                VStack(alignment: .leading, spacing: 6) {
                    StatRow(label: "☀ Sunrise", value: displayTime(times.sunrise ?? times.sunriseUTC))
                    StatRow(label: "☀ Sunset", value: displayTime(times.sunset ?? times.sunsetUTC))
                    StatRow(label: "☽ Moonrise", value: displayTime(times.moonrise))
                    StatRow(label: "☽ Moonset", value: displayTime(times.moonset))
                    if let passes = space.issPasses {
                        Divider().background(theme.dimColor)
                        StatRow(label: "ISS passes", value: passes.time)
                        StatRow(label: "Pass length", value: passes.duration)
                        StatRow(label: "Brightness", value: passes.brightness)
                    }
                }
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func planetsPanel(_ space: SpaceData, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Planets")
            HStack {
                Text("Planet").frame(maxWidth: .infinity, alignment: .leading)
                Text("Altitude").frame(width: 74, alignment: .trailing)
                Text("Azimuth").frame(width: 74, alignment: .trailing)
                Text("").frame(width: 74, alignment: .trailing)
            }
            .font(Retro.font(10, weight: .bold))
            .foregroundColor(theme.accent2Color)
            ForEach(space.planets) { planet in
                HStack {
                    Text(planet.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(theme.primaryColor)
                    Text(String(format: "%.1f°", planet.altitude))
                        .frame(width: 74, alignment: .trailing)
                        .foregroundColor(theme.primaryColor)
                    Text(String(format: "%.1f°", planet.azimuth))
                        .frame(width: 74, alignment: .trailing)
                        .foregroundColor(theme.primaryColor)
                    Text(planet.visible ? "● visible" : "○ below")
                        .frame(width: 74, alignment: .trailing)
                        .foregroundColor(planet.visible ? theme.accent1Color : theme.dimColor)
                }
                .font(Retro.font(Retro.smallSize))
                .padding(.vertical, 1)
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func issPanel(_ space: SpaceData, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "ISS · Live", badge: space.iss?.live == true ? "LIVE" : "CACHED")
            if let iss = space.iss {
                Text(String(format: "lat %.2f°, lon %.2f° · alt %.1f km · %@ km/h",
                            iss.latitude, iss.longitude, iss.altitudeKm,
                            iss.velocityKmh.formatted(.number.precision(.fractionLength(0)))))
                    .font(Retro.font(Retro.bodySize, weight: .semibold))
                    .foregroundColor(theme.primaryColor)
                    .phosphorGlow(theme, radius: 3)
                if let vis = iss.visibility {
                    StatRow(label: "Visibility", value: vis)
                }
            } else {
                Text("ISS position unavailable (offline).")
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.dimColor)
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    /// Open-Meteo times arrive as "2026-10-24T06:38"; ISO UTC strings
    /// get parsed and localized. Display honors the 12h/24h setting.
    private func displayTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "--:--" }
        if raw.contains("T"), !raw.hasSuffix("Z"), !raw.contains("+") {
            return APIClient.formatTime(raw, timeFormat: store.timeFormatName)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return raw }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = store.timeFormat12h ? "h:mm a" : "HH:mm"
        return out.string(from: date)
    }
}

import SwiftUI

/// SOLAR panel: sunspot / flux / Kp gauges, solar-wind readouts, and
/// the Kp forecast bar chart — mirroring the GUI solar panel.
struct SolarView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.theme
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                PanelStateView(state: store.solarState,
                               retry: { Task { await store.refreshSolar() } }) { solar in
                    ScrollView {
                        VStack(spacing: 14) {
                            gaugePanel(solar, theme: theme)
                            windPanel(solar, theme: theme)
                            if !solar.forecastSorted.isEmpty {
                                forecastPanel(solar, theme: theme)
                            }
                            if !solar.alerts.isEmpty {
                                alertsPanel(solar, theme: theme)
                            }
                        }
                        .padding(12)
                    }
                    .refreshable { await store.refreshSolar() }
                }
            }
            .navigationTitle("ULTRASYNC · SOLAR")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { if store.solarState.value == nil { await store.refreshSolar() } }
    }

    private func gaugePanel(_ solar: SolarData, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Solar Activity",
                        badge: (solar.stale ?? false) ? "CACHED" : "LIVE")
            HStack(spacing: 12) {
                GaugeView(value: solar.sunspotNumber, maxValue: 300,
                          label: "Sunspot #",
                          display: solar.sunspotNumber.map { String(format: "%.0f", $0) } ?? "--")
                GaugeView(value: solar.solarFlux, maxValue: 300,
                          label: "Solar Flux",
                          display: solar.solarFlux.map { String(format: "%.0f", $0) } ?? "--")
                GaugeView(value: solar.geomagnetic?.kpIndex, maxValue: 9,
                          label: "Kp Index",
                          display: solar.geomagnetic.map { String(format: "%.0f", $0.kpIndex) } ?? "--")
            }
            if let geo = solar.geomagnetic {
                HStack(spacing: 16) {
                    StatRow(label: "Condition", value: geo.label)
                    StatRow(label: "A Index", value: String(format: "%.0f", geo.aIndex))
                    StatRow(label: "Aurora prob", value: "\(geo.auroraProbability)%")
                }
            }
            if let regions = solar.activeRegions {
                StatRow(label: "Active regions", value: "\(regions)")
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func windPanel(_ solar: SolarData, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(title: "Solar Wind")
            if let wind = solar.solarWind {
                StatRow(label: "Speed", value: wind.speed.map { String(format: "%.0f km/s", $0) } ?? "--")
                StatRow(label: "Density", value: wind.density.map { String(format: "%.2f p/cm³", $0) } ?? "--")
                StatRow(label: "Temperature", value: wind.temperature.map { String(format: "%.0f K", $0) } ?? "--")
                StatRow(label: "Bz (GSM)", value: wind.bz.map { String(format: "%.2f nT", $0) } ?? "--")
                StatRow(label: "Bt", value: wind.bt.map { String(format: "%.2f nT", $0) } ?? "--")
            } else {
                Text("Solar wind feed unavailable.")
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.dimColor)
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func forecastPanel(_ solar: SolarData, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Kp Forecast")
            KpBarChart(entries: solar.forecastSorted.prefix(8).map {
                (date: $0.date, kp: $0.day.kpIndex ?? 0)
            })
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func alertsPanel(_ solar: SolarData, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(title: "Space Weather Alerts")
            ForEach(solar.alerts, id: \.self) { alert in
                Text(alert)
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.accent3Color)
            }
        }
        .padding(12)
        .retroPanel(theme)
    }
}

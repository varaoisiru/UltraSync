import SwiftUI

/// Settings: theme picker with live swatches, units + time format,
/// the data-mode / UltraSync server configuration, and about info.
struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager
    @State private var serverDraft = ""
    @State private var reconnectMessage: String? = nil
    @Namespace private var themeGlass

    var body: some View {
        let theme = themeManager.theme
        NavigationStack {
            ZStack {
                theme.backdropView.ignoresSafeArea()
                ScrollView {
                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 14) {
                            themePanel(theme: theme)
                            unitsPanel(theme: theme)
                            dataPanel(theme: theme)
                            aboutPanel(theme: theme)
                        }
                    }
                    .padding(12)
                }
            }
            .navigationTitle("ULTRASYNC · SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sensoryFeedback(.selection, trigger: themeManager.theme.id)
        .onAppear { serverDraft = store.backendURLString }
    }

    // MARK: theme

    private func themePanel(theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Theme")
            GlassEffectContainer(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ThemeCatalog.all) { palette in
                        Button {
                            themeManager.select(palette)
                        } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: 3) {
                                    swatch(palette.primaryColor)
                                    swatch(palette.accent1Color)
                                    swatch(palette.accent2Color)
                                    swatch(palette.accent3Color)
                                }
                                Text(palette.name)
                                    .font(Retro.font(11, weight: .bold))
                                    .foregroundColor(palette.primaryColor)
                                Spacer()
                                if themeManager.theme.id == palette.id {
                                    Text("●")
                                        .foregroundColor(palette.accent1Color)
                                        .font(Retro.font(11))
                                }
                            }
                            .padding(9)
                            .glassEffect(
                                .regular
                                    .tint(palette.bgColor.opacity(0.88))
                                    .interactive(),
                                in: .rect(cornerRadius: 12))
                            .glassEffectID(
                                themeManager.theme.id == palette.id
                                    ? "themeSelection" : palette.id,
                                in: themeGlass)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(themeManager.theme.id == palette.id
                                        ? palette.accent1Color : palette.dimColor.opacity(0.6),
                                        lineWidth: themeManager.theme.id == palette.id ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Toggle(isOn: $store.showScanlines) {
                Text("CRT scanlines")
                    .font(Retro.font(Retro.bodySize))
                    .foregroundColor(theme.primaryColor)
            }
            .tint(theme.accent1Color)
        }
        .padding(12)
        .retroPanel(theme)
        .retroScrollTransition()
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 13, height: 13)
    }

    // MARK: units

    private func unitsPanel(theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Units & Time")
            HStack {
                Text("Temperature")
                    .font(Retro.font(Retro.bodySize))
                    .foregroundColor(theme.primaryColor)
                Spacer()
                Picker("Temperature", selection: $store.imperialUnits) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            HStack {
                Text("Time format")
                    .font(Retro.font(Retro.bodySize))
                    .foregroundColor(theme.primaryColor)
                Spacer()
                Picker("Time format", selection: $store.timeFormat12h) {
                    Text("24h").tag(false)
                    Text("12h").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            Text("Unit changes re-fetch weather in standalone mode; in server mode the server's configured units win.")
                .font(Retro.font(10))
                .foregroundColor(theme.dimColor)
        }
        .padding(12)
        .retroPanel(theme)
        .retroScrollTransition()
        .onChange(of: store.imperialUnits) { _, _ in
            Task { await store.refreshWeather() }
        }
    }

    // MARK: data mode

    private func dataPanel(theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Data Source")
            Picker("Data mode", selection: $store.mode) {
                ForEach(DataMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if store.mode == .backend {
                TextField("UltraSync server URL", text: $serverDraft)
                    .retroTextField(theme)
                Button("APPLY & RECONNECT") {
                    Task { await reconnect() }
                }
                .font(Retro.font(Retro.bodySize, weight: .bold))
                .foregroundColor(theme.accent1Color)
                .buttonStyle(.glass)
                if let reconnectMessage {
                    Text(reconnectMessage)
                        .font(Retro.font(Retro.smallSize))
                        .foregroundColor(theme.accent2Color)
                }
            } else {
                Text("Standalone: the app talks directly to Open-Meteo, NOAA SWPC, your RSS feeds, and wheretheiss.at — the same free, key-less sources as the Python app. Location comes from ip-api geolocation.")
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.primaryColor.opacity(0.85))
            }
            StatRow(label: "Location",
                    value: store.place.city ?? String(format: "%.2f, %.2f",
                                                       store.place.latitude,
                                                       store.place.longitude))
            if let version = store.backendVersion {
                StatRow(label: "Server version", value: version)
            }
        }
        .padding(12)
        .retroPanel(theme)
        .retroScrollTransition()
        .onChange(of: store.mode) { _, _ in
            Task { await store.boot() }
        }
    }

    private func reconnect() async {
        store.backendURLString = serverDraft
        await store.resolveLocation()
        if store.backendVersion != nil {
            reconnectMessage = "Connected — server v\(store.backendVersion!)."
        } else {
            reconnectMessage = "Could not reach a server at that URL."
        }
        await store.boot()
    }

    // MARK: about

    private func aboutPanel(theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(title: "About")
            Text("UltraSync 2.0.0 — native iOS fork of the UltraSync dashboard (merged from Ultrareader + SolarSync).")
                .font(Retro.font(Retro.smallSize))
                .foregroundColor(theme.primaryColor.opacity(0.9))
            Text("Data: Open-Meteo · NOAA SWPC · wheretheiss.at · RSS feeds — all free, no keys.")
                .font(Retro.font(Retro.smallSize))
                .foregroundColor(theme.primaryColor.opacity(0.9))
            Text("Signed with free provisioning (Personal Team): installs on your own iPhone, signature expires after 7 days — re-run from Xcode to renew. No App Store distribution.")
                .font(Retro.font(Retro.smallSize))
                .foregroundColor(theme.dimColor)
        }
        .padding(12)
        .retroPanel(theme)
        .retroScrollTransition()
    }
}

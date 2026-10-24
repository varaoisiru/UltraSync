import SwiftUI

/// HUE panel: real light control when a bridge is configured — via
/// the UltraSync server in backend mode, or directly against the
/// bridge in standalone mode — and the clean not-configured state
/// with the bridge settings form otherwise (same contract as the GUI).
struct HueView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager
    @State private var bridgeIPDraft = ""
    @State private var credentialDraft = ""
    @State private var fxList: [HueFXEffect] = []
    @State private var fxSelection: Int = 0

    var body: some View {
        let theme = themeManager.theme
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                PanelStateView(state: store.hueState,
                               retry: { Task { await store.refreshHue() } }) { hue in
                    ScrollView {
                        VStack(spacing: 14) {
                            if hue.configured {
                                lightsPanel(hue, theme: theme)
                                if store.mode == .backend {
                                    fxPanel(hue, theme: theme)
                                }
                            } else {
                                notConfiguredPanel(theme: theme)
                            }
                        }
                        .padding(12)
                    }
                    .refreshable { await store.refreshHue() }
                }
            }
            .navigationTitle("ULTRASYNC · HUE")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if store.hueState.value == nil { await store.refreshHue() }
            bridgeIPDraft = store.hueBridgeIP
            fxList = await store.fetchFXList()
        }
    }

    // MARK: configured

    private func lightsPanel(_ hue: HueState, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Philips Hue", badge: "CONFIGURED")
            HStack {
                Text("Bridge \(hue.bridgeIP ?? "--")")
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.dimColor)
                Spacer()
                Button("All on") { Task { await store.setAllLights(on: true) } }
                Button("All off") { Task { await store.setAllLights(on: false) } }
            }
            .font(Retro.font(Retro.smallSize, weight: .bold))
            .foregroundColor(theme.accent1Color)

            if store.mode == .backend {
                Toggle(isOn: Binding(
                    get: { hue.syncConditions },
                    set: { newValue in Task { await store.setHueSync(enabled: newValue) } }
                )) {
                    Text("Sync to conditions")
                        .font(Retro.font(Retro.bodySize))
                        .foregroundColor(theme.primaryColor)
                }
                .tint(theme.accent1Color)
            }

            if hue.lights.isEmpty {
                Text("Bridge reachable, but no lights returned.")
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.dimColor)
            }
            ForEach(hue.lights) { light in
                LightRow(light: light)
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func fxPanel(_ hue: HueState, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "FX Library",
                        badge: hue.fx?.playing != nil ? "PLAYING" : nil)
            if fxList.isEmpty {
                Text("Effect list unavailable from the server.")
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.dimColor)
            } else {
                Picker("Effect", selection: $fxSelection) {
                    ForEach(fxList) { fx in
                        Text("\(fx.index + 1). \(fx.name)").tag(fx.index)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.primaryColor)
                if let fx = fxList.first(where: { $0.index == fxSelection }) {
                    Text(fx.description)
                        .font(Retro.font(Retro.smallSize))
                        .foregroundColor(theme.primaryColor.opacity(0.75))
                }
                HStack(spacing: 12) {
                    Button("▶ Play FX") {
                        Task { await store.playFX(index: fxSelection) }
                    }
                    Button("■ Stop") {
                        Task { await store.playFX(index: nil) }
                    }
                    if let playing = hue.fx?.playing {
                        Text(playing.name)
                            .font(Retro.font(Retro.smallSize, weight: .bold))
                            .foregroundColor(theme.accent2Color)
                    }
                }
                .font(Retro.font(Retro.bodySize, weight: .bold))
                .foregroundColor(theme.accent1Color)
            }
        }
        .padding(12)
        .retroPanel(theme)
        .task { fxList = await store.fetchFXList() }
    }

    // MARK: not configured

    private func notConfiguredPanel(theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Philips Hue", badge: "NOT CONFIGURED")
            Text(store.mode == .backend
                 ? "No bridge is configured on the UltraSync server. Enter the bridge IP and API key below to save them to the server, or set HUE_BRIDGE_IP / HUE_API_KEY in its config."
                 : "Hue bridge not configured — add the bridge IP and bridge username below. (Or in the terminal app: config file ~/.config/ultrasync/config.json, or env HUE_BRIDGE_IP / HUE_API_KEY.)")
                .font(Retro.font(Retro.smallSize))
                .foregroundColor(theme.primaryColor.opacity(0.85))
            TextField("Bridge IP (e.g. 192.168.1.11)", text: $bridgeIPDraft)
                .retroTextField(theme)
            SecureField(store.mode == .backend ? "API key" : "Bridge username",
                        text: $credentialDraft)
                .retroTextField(theme)
            Button("SAVE & TEST") {
                Task { await saveBridge() }
            }
            .font(Retro.font(Retro.bodySize, weight: .bold))
            .foregroundColor(theme.bgColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(theme.primaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("To create a bridge username/API key, press the link button on the bridge, then POST {\"devicetype\":\"ultrasync#ios\"} to http://BRIDGE_IP/api.")
                .font(Retro.font(10))
                .foregroundColor(theme.dimColor)
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func saveBridge() async {
        let ip = bridgeIPDraft.trimmingCharacters(in: .whitespaces)
        let cred = credentialDraft.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty, !cred.isEmpty else { return }
        switch store.mode {
        case .standalone:
            store.hueBridgeIP = ip
            store.hueUsername = cred
        case .backend:
            store.hueBridgeIP = ip
            if let base = store.backendBaseURL {
                _ = try? await store.client.postJSON(
                    to: base.appendingPathComponent("api/config"),
                    body: ["hue": ["bridge_ip": ip, "api_key": cred]])
            }
        }
        await store.refreshHue()
    }
}

/// One light: name, reachability, on/off toggle, brightness slider.
struct LightRow: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager
    let light: HueLight
    @State private var brightness: Double

    init(light: HueLight) {
        self.light = light
        _brightness = State(initialValue: light.brightnessFraction)
    }

    var body: some View {
        let theme = themeManager.theme
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("💡 \(light.name)")
                    .font(Retro.font(Retro.bodySize, weight: .semibold))
                    .foregroundColor(light.reachable ? theme.primaryColor : theme.dimColor)
                if !light.reachable {
                    Text("UNREACHABLE")
                        .font(Retro.font(9, weight: .bold))
                        .foregroundColor(theme.accent3Color)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { light.on },
                    set: { newValue in Task { await store.setLight(id: light.id, on: newValue) } }
                ))
                .labelsHidden()
                .tint(theme.accent2Color)
            }
            Slider(value: $brightness, in: 0...1) { editing in
                if !editing {
                    Task { await store.setLight(id: light.id, brightness: brightness) }
                }
            }
            .tint(theme.accent1Color)
            .disabled(!light.on)
        }
        .padding(.vertical, 4)
        .onChange(of: light.bri) { _, _ in
            brightness = light.brightnessFraction
        }
    }
}

extension View {
    /// Monospaced dark text field matching the panel skin.
    func retroTextField(_ theme: ThemePalette) -> some View {
        self
            .font(Retro.font(Retro.bodySize))
            .foregroundColor(theme.primaryColor)
            .padding(10)
            .background(theme.bgColor.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(theme.dimColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
    }
}

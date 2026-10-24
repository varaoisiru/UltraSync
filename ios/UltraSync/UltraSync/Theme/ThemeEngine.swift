import SwiftUI

/// One UltraSync theme palette. Hex values are ported verbatim from
/// ultrasync/themes.py (SolarSync's canonical palettes) — the parity
/// checker in ios/tools/check_parity.py asserts they stay identical.
struct ThemePalette: Identifiable, Equatable {
    let id: String          // canonical key, e.g. "cyberfire"
    let name: String        // display name, e.g. "Cyberfire"
    let bg: String
    let primary: String
    let accent1: String
    let accent2: String
    let accent3: String
    let dim: String

    var bgColor: Color { Color(hex: bg) }
    var primaryColor: Color { Color(hex: primary) }
    var accent1Color: Color { Color(hex: accent1) }
    var accent2Color: Color { Color(hex: accent2) }
    var accent3Color: Color { Color(hex: accent3) }
    var dimColor: Color { Color(hex: dim) }

    /// Slightly lifted panel surface derived from the background.
    var panelColor: Color { Color.panelLifted(fromHex: bg) }
}

enum ThemeCatalog {
    static let all: [ThemePalette] = [
        ThemePalette(id: "cyberfire", name: "Cyberfire", bg: "#0a0a0a", primary: "#00ff41", accent1: "#ff6600", accent2: "#ffaa00", accent3: "#ff3300", dim: "#006600"),
        ThemePalette(id: "midnight", name: "Midnight Ice", bg: "#0a0a0f", primary: "#b0b0b0", accent1: "#4a9eff", accent2: "#00d4aa", accent3: "#8855ff", dim: "#333344"),
        ThemePalette(id: "phosphor", name: "Phosphor Green", bg: "#0a0a0a", primary: "#33ff33", accent1: "#00cc00", accent2: "#009900", accent3: "#66ff66", dim: "#003300"),
        ThemePalette(id: "solarflare", name: "Solar Flare", bg: "#0f0a00", primary: "#ffcc00", accent1: "#ff6600", accent2: "#ff3300", accent3: "#ffffff", dim: "#663300"),
        ThemePalette(id: "aurora", name: "Aurora Borealis", bg: "#050510", primary: "#e0e0ff", accent1: "#00ff88", accent2: "#ff44aa", accent3: "#44aaff", dim: "#220033"),
        ThemePalette(id: "neonviolet", name: "Neon Violet", bg: "#0a0010", primary: "#ff00ff", accent1: "#00ffff", accent2: "#ff0088", accent3: "#8800ff", dim: "#330044"),
        ThemePalette(id: "deepocean", name: "Deep Ocean", bg: "#000a10", primary: "#00ffff", accent1: "#0088ff", accent2: "#00ff88", accent3: "#ff8800", dim: "#002233"),
        ThemePalette(id: "toxicwaste", name: "Toxic Waste", bg: "#0a0a00", primary: "#00ff00", accent1: "#ffff00", accent2: "#ff00ff", accent3: "#00ffff", dim: "#333300"),
    ]

    static let defaultID = "cyberfire"

    static func palette(for id: String) -> ThemePalette {
        all.first { $0.id == id } ?? all[0]
    }

    static func next(after id: String) -> ThemePalette {
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return all[0] }
        return all[(idx + 1) % all.count]
    }
}

/// Observable theme switcher, mirroring the Python app's persisted
/// preferences.theme value. Views read `theme` from the environment.
final class ThemeManager: ObservableObject {
    @Published private(set) var theme: ThemePalette
    @AppStorage("us_theme") private var storedID: String = ThemeCatalog.defaultID

    init() {
        let stored = UserDefaults.standard.string(forKey: "us_theme") ?? ThemeCatalog.defaultID
        theme = ThemeCatalog.palette(for: stored)
    }

    func select(_ palette: ThemePalette) {
        theme = palette
        storedID = palette.id
    }

    func select(id: String) {
        select(ThemeCatalog.palette(for: id))
    }

    func cycle() {
        select(ThemeCatalog.next(after: theme.id))
    }
}

extension Color {
    /// "#rrggbb" (or "rrggbb") → Color, matching themes.py hex_to_rgb.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// The web GUI's panels sit one step above the page background.
    /// Emulated by lifting the base color toward white in sRGB space.
    static func panelLifted(fromHex hex: String) -> Color {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let lift = 14.0 / 255.0
        let r = min(1.0, Double((value >> 16) & 0xFF) / 255.0 + lift)
        let g = min(1.0, Double((value >> 8) & 0xFF) / 255.0 + lift)
        let b = min(1.0, Double(value & 0xFF) / 255.0 + lift)
        return Color(red: r, green: g, blue: b)
    }
}

import SwiftUI

/// Shared retro-phosphor styling: monospaced type, glowing headers,
/// thin neon panel borders, optional scanline overlay — the native
/// counterpart of the web GUI's CSS skin.
enum Retro {
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let headerSize: CGFloat = 15
    static let bodySize: CGFloat = 13
    static let smallSize: CGFloat = 11
}

extension View {
    /// Panel surface: lifted background + 1pt primary border, the
    /// GUI's signature box.
    func retroPanel(_ theme: ThemePalette) -> some View {
        self
            .background(theme.panelColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.primaryColor.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Phosphor glow for headlines and big readouts.
    func phosphorGlow(_ theme: ThemePalette, radius: CGFloat = 6) -> some View {
        self.shadow(color: theme.primaryColor.opacity(0.65), radius: radius)
            .shadow(color: theme.primaryColor.opacity(0.3), radius: radius * 2)
    }
}

/// Section header used at the top of every panel, with an optional
/// LIVE/CACHED-style badge.
struct PanelHeader: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    var badge: String? = nil

    var body: some View {
        let theme = themeManager.theme
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Retro.font(Retro.headerSize, weight: .bold))
                .foregroundColor(theme.accent1Color)
                .phosphorGlow(theme, radius: 4)
            if let badge {
                Text(badge)
                    .font(Retro.font(9, weight: .bold))
                    .foregroundColor(theme.primaryColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(theme.primaryColor.opacity(0.7), lineWidth: 1)
                    )
            }
            Spacer()
        }
    }
}

/// CRT scanline overlay (toggleable in Settings).
struct ScanlinesView: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                context.fill(Path(rect), with: .color(.black.opacity(0.14)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

/// Uniform loading / error presentation for a panel.
struct PanelStateView<T, Content: View>: View {
    @EnvironmentObject var themeManager: ThemeManager
    let state: PanelState<T>
    let retry: () -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        let theme = themeManager.theme
        switch state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(theme.primaryColor)
                Text("LOADING…")
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.dimColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 12) {
                Text("⚠ OFFLINE / ERROR")
                    .font(Retro.font(Retro.bodySize, weight: .bold))
                    .foregroundColor(theme.accent3Color)
                Text(message)
                    .font(Retro.font(Retro.smallSize))
                    .foregroundColor(theme.primaryColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("RETRY", action: retry)
                    .font(Retro.font(Retro.bodySize, weight: .bold))
                    .foregroundColor(theme.bgColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        case .loaded(let value):
            content(value)
        }
    }
}

/// Small label/value stat line used across the panels.
struct StatRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        let theme = themeManager.theme
        HStack {
            Text(label)
                .font(Retro.font(Retro.smallSize))
                .foregroundColor(theme.accent2Color)
            Spacer()
            Text(value)
                .font(Retro.font(Retro.smallSize, weight: .semibold))
                .foregroundColor(valueColor ?? theme.primaryColor)
        }
    }
}

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
    /// Panel surface: an iOS 26 Liquid Glass card tinted by the theme's
    /// panel color over a hairline primary stroke — the GUI's signature
    /// box, in glass. Panels on a screen sit inside a
    /// GlassEffectContainer so neighbouring glass blends correctly.
    func retroPanel(_ theme: ThemePalette) -> some View {
        self
            .glassEffect(.regular.tint(theme.panelColor.opacity(0.42)),
                         in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(theme.primaryColor.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Subtle scroll parallax for hero content: as the panel travels up
    /// the scroll view its foreground drifts down a fraction of the
    /// distance, so it reads as nearer than the panel surface. Pure
    /// offset — no state, no per-frame work beyond the scroll itself.
    func retroParallax(strength: CGFloat = 0.16) -> some View {
        self.visualEffect { content, proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let shift = minY < 0 ? -minY * strength : 0
            return content.offset(y: shift)
        }
    }

    /// Card entrance/exit treatment for panels in scrolling stacks:
    /// gentle scale + fade (+ a whisper of blur at the extremes) tied
    /// interactively to scroll position.
    func retroScrollTransition() -> some View {
        self.scrollTransition(.interactive, axis: .vertical) { content, phase in
            let amount = abs(phase.value)
            return content
                .opacity(1 - amount * 0.3)
                .scaleEffect(1 - amount * 0.04)
                .blur(radius: amount * 2.5)
        }
    }

    /// Phosphor glow for headlines and big readouts.
    func phosphorGlow(_ theme: ThemePalette, radius: CGFloat = 6) -> some View {
        self.shadow(color: theme.primaryColor.opacity(0.65), radius: radius)
            .shadow(color: theme.primaryColor.opacity(0.3), radius: radius * 2)
    }
}

/// Rich page backdrop the glass panels refract against: the theme
/// background washed with soft radial glows of its own accents and a
/// panel-tinted diagonal sheen. Replaces the flat background fills.
struct ThemeBackdrop: View {
    let theme: ThemePalette

    var body: some View {
        ZStack {
            theme.bgColor
            RadialGradient(
                colors: [theme.accent2Color.opacity(0.20), Color.clear],
                center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(
                colors: [theme.accent1Color.opacity(0.16), Color.clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 460)
            LinearGradient(
                colors: [theme.panelColor.opacity(0.25), Color.clear,
                         theme.dimColor.opacity(0.18)],
                startPoint: .top, endPoint: .bottom)
        }
    }
}

extension ThemePalette {
    /// The theme's page backdrop (see ThemeBackdrop).
    var backdropView: ThemeBackdrop { ThemeBackdrop(theme: self) }
}

/// Section header used at the top of every panel, with an optional
/// LIVE/CACHED-style glass badge and an optional status symbol
/// (pulsing while the panel's data is live).
struct PanelHeader: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    var badge: String? = nil
    var symbol: String? = nil

    var body: some View {
        let theme = themeManager.theme
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(Retro.font(Retro.headerSize, weight: .bold))
                    .foregroundColor(theme.accent1Color)
                    .symbolEffect(.pulse, options: .repeating,
                                  isActive: badge == "LIVE")
            }
            Text(title.uppercased())
                .font(Retro.font(Retro.headerSize, weight: .bold))
                .foregroundColor(theme.accent1Color)
                .phosphorGlow(theme, radius: 4)
            if let badge {
                Text(badge)
                    .font(Retro.font(9, weight: .bold))
                    .foregroundColor(theme.primaryColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(theme.primaryColor.opacity(0.16)),
                                 in: .capsule)
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

/// Uniform loading / error presentation for a panel. State changes
/// crossfade/slide on a spring (loading → loaded, error → loaded)
/// instead of hard cuts, and arriving at loaded fires a success
/// haptic.
struct PanelStateView<T, Content: View>: View {
    @EnvironmentObject var themeManager: ThemeManager
    let state: PanelState<T>
    let retry: () -> Void
    @ViewBuilder let content: (T) -> Content

    /// Case tag for animation/haptic triggers (PanelState is not
    /// Equatable; the tag captures everything the UI reacts to).
    private var stateTag: Int {
        switch state {
        case .idle: return 0
        case .loading: return 1
        case .loaded: return 2
        case .error: return 3
        }
    }

    var body: some View {
        let theme = themeManager.theme
        Group {
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
                .transition(.opacity)
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
                        .buttonStyle(.glassProminent)
                        .tint(theme.primaryColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .loaded(let value):
                content(value)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: stateTag)
        .sensoryFeedback(trigger: stateTag) { _, newTag in
            newTag == 2 ? .success : nil
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

import SwiftUI

/// AMBIENT tab (2.0): the native counterpart of the web GUI's ambient
/// mode — a slow, full-screen cycle through the day's highlights
/// (top headline, weather, geomagnetic state, moon) in oversized
/// type on a Liquid Glass card. Slides crossfade every six seconds;
/// tapping advances immediately. Everything reads from the shared
/// DataStore panels, so ambient shows exactly what the tabs show.
struct AmbientView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager
    @State private var slideIndex = 0
    private let cycle = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private struct Slide {
        let kicker: String
        let big: String
        let sub: String
    }

    private var slides: [Slide] {
        var out: [Slide] = []
        if let news = store.newsState.value, let top = news.articles.first {
            out.append(Slide(
                kicker: "TOP HEADLINE · \(top.source.uppercased())",
                big: top.headline,
                sub: news.totalUnread > 0 ? "\(news.totalUnread) unread stories" : "all caught up"))
        }
        if let wx = store.weatherState.value, wx.ok {
            let t = wx.current.temperature.map { String(format: "%.0f", $0) } ?? "--"
            let f = wx.current.feelsLike.map { String(format: "%.0f", $0) } ?? "--"
            out.append(Slide(
                kicker: "WEATHER",
                big: "\(wx.current.icon) \(t)\(wx.unitSymbol)",
                sub: "\(wx.current.description) · feels \(f)\(wx.unitSymbol)"))
        }
        if let sol = store.solarState.value, let geo = sol.geomagnetic {
            out.append(Slide(
                kicker: "SOLAR · GEOMAGNETIC",
                big: String(format: "Kp %.0f", geo.kpIndex),
                sub: "\(geo.label) · aurora probability \(geo.auroraProbability)%"))
        }
        if let sp = store.spaceState.value {
            var sub = String(format: "%.0f%% illuminated", sp.moon.illumination)
            if let iss = sp.iss {
                sub += String(format: " · ISS at %.1f°, %.1f°", iss.latitude, iss.longitude)
            }
            out.append(Slide(
                kicker: "SPACE · MOON",
                big: "\(sp.moon.icon) \(sp.moon.name)",
                sub: sub))
        }
        if out.isEmpty {
            out.append(Slide(kicker: "ULTRASYNC", big: "▚", sub: "waiting for data…"))
        }
        return out
    }

    var body: some View {
        let theme = themeManager.theme
        let slides = slides
        let slide = slides[slideIndex % slides.count]
        ZStack {
            theme.backdropView.ignoresSafeArea()
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 18) {
                    Text(slide.kicker)
                        .font(Retro.font(13, weight: .bold))
                        .tracking(4)
                        .foregroundColor(theme.accent2Color)
                        .multilineTextAlignment(.center)
                    Text(slide.big)
                        .font(Retro.font(40, weight: .bold))
                        .foregroundColor(theme.primaryColor)
                        .phosphorGlow(theme, radius: 8)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.55)
                    if !slide.sub.isEmpty {
                        Text(slide.sub)
                            .font(Retro.font(16))
                            .foregroundColor(theme.accent1Color)
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 7) {
                        ForEach(slides.indices, id: \.self) { i in
                            Circle()
                                .fill(i == slideIndex % slides.count
                                      ? theme.primaryColor : theme.dimColor.opacity(0.5))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(30)
                .frame(maxWidth: .infinity)
                .retroPanel(theme)
                .id(slideIndex % slides.count)
                .transition(.opacity)
            }
            .padding(18)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance(slides.count) }
        .onReceive(cycle) { _ in advance(slides.count) }
        .task {
            if store.newsState.value == nil { await store.refreshNews() }
            if store.weatherState.value == nil { await store.refreshWeather() }
            if store.solarState.value == nil { await store.refreshSolar() }
            if store.spaceState.value == nil { await store.refreshSpace() }
        }
    }

    private func advance(_ count: Int) {
        guard count > 0 else { return }
        withAnimation(.easeInOut(duration: 1.1)) {
            slideIndex = (slideIndex + 1) % count
        }
    }
}

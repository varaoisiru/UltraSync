import SwiftUI

/// WEATHER panel: current conditions, a Canvas 24-hour temperature
/// curve, and the 7-day outlook — mirroring the GUI weather panel.
struct WeatherView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.theme
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                PanelStateView(state: store.weatherState,
                               retry: { Task { await store.refreshWeather() } }) { wx in
                    ScrollView {
                        VStack(spacing: 14) {
                            currentPanel(wx, theme: theme)
                            chartPanel(wx, theme: theme)
                            dailyPanel(wx, theme: theme)
                        }
                        .padding(12)
                    }
                    .refreshable { await store.refreshWeather() }
                }
            }
            .navigationTitle("ULTRASYNC · WEATHER")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { if store.weatherState.value == nil { await store.refreshWeather() } }
    }

    private func currentPanel(_ wx: WeatherData, theme: ThemePalette) -> some View {
        let c = wx.current
        return VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Weather",
                        badge: (wx.stale ?? false) ? "CACHED" : "LIVE")
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(c.icon)
                            .font(.system(size: 30))
                        Text(c.temperature.map { String(format: "%.0f", $0) } ?? "--")
                            .font(Retro.font(44, weight: .bold))
                            .foregroundColor(theme.accent2Color)
                            .phosphorGlow(theme)
                        Text(wx.unitSymbol)
                            .font(Retro.font(20, weight: .bold))
                            .foregroundColor(theme.accent2Color)
                    }
                    Text(c.description)
                        .font(Retro.font(Retro.bodySize, weight: .semibold))
                        .foregroundColor(theme.primaryColor)
                    Text("feels \(c.feelsLike.map { String(format: "%.0f", $0) } ?? "--")\(wx.unitSymbol)")
                        .font(Retro.font(Retro.smallSize))
                        .foregroundColor(theme.primaryColor.opacity(0.7))
                    if let city = wx.location.city {
                        Text("\(city) · \(String(format: "%.2f", wx.location.latitude)), \(String(format: "%.2f", wx.location.longitude))")
                            .font(Retro.font(10))
                            .foregroundColor(theme.dimColor)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    StatRow(label: "Humidity", value: c.humidity.map { String(format: "%.0f%%", $0) } ?? "--")
                    StatRow(label: "Wind", value: windText(c, symbol: wx.unitSymbol))
                    StatRow(label: "Clouds", value: c.cloudCover.map { String(format: "%.0f%%", $0) } ?? "--")
                    StatRow(label: "Precip", value: c.precipitation.map { String(format: "%.1f mm", $0) } ?? "--")
                }
                .frame(maxWidth: 150)
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func windText(_ c: WeatherData.CurrentConditions, symbol: String) -> String {
        guard let speed = c.windSpeed else { return "--" }
        return String(format: "%.1f km/h %@", speed, c.windDirection)
    }

    /// Next 24 hourly points starting at the current hour, like the
    /// GUI curve (which windows the hourly series at "now").
    private func chartPanel(_ wx: WeatherData, theme: ThemePalette) -> some View {
        let points = Array(wx.hourly.prefix(24))
        return VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "24H Temperature")
            TemperatureChart(points: points, theme: theme)
                .frame(height: 110)
            HStack {
                ForEach(Array(stride(from: 0, to: points.count, by: 4)), id: \.self) { i in
                    Text(points[i].label)
                        .font(Retro.font(9))
                        .foregroundColor(theme.dimColor)
                    if i + 4 < points.count { Spacer() }
                }
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    private func dailyPanel(_ wx: WeatherData, theme: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "7-Day Outlook")
            ForEach(wx.daily) { day in
                HStack(spacing: 10) {
                    Text(day.label)
                        .font(Retro.font(Retro.smallSize, weight: .bold))
                        .foregroundColor(theme.accent2Color)
                        .frame(width: 36, alignment: .leading)
                    Text(day.icon)
                        .font(.system(size: 14))
                        .frame(width: 24)
                    Text(day.min.map { String(format: "%.0f°", $0) } ?? "--")
                        .font(Retro.font(Retro.smallSize))
                        .foregroundColor(theme.primaryColor.opacity(0.6))
                        .frame(width: 36, alignment: .trailing)
                    tempBar(day: day, all: wx.daily, theme: theme)
                    Text(day.max.map { String(format: "%.0f°", $0) } ?? "--")
                        .font(Retro.font(Retro.smallSize, weight: .bold))
                        .foregroundColor(theme.primaryColor)
                        .frame(width: 36, alignment: .leading)
                    Text(day.precipProbability.map { String(format: "%.0f%%", $0) } ?? "")
                        .font(Retro.font(10))
                        .foregroundColor(theme.accent3Color)
                        .frame(width: 38, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .retroPanel(theme)
    }

    /// Inline min–max range bar scaled to the week's extremes.
    private func tempBar(day: WeatherData.DayForecast,
                         all: [WeatherData.DayForecast],
                         theme: ThemePalette) -> some View {
        let lo = all.compactMap(\.min).min() ?? 0
        let hi = all.compactMap(\.max).max() ?? 1
        let span = max(1, hi - lo)
        let start = CGFloat(((day.min ?? lo) - lo) / span)
        let width = CGFloat(max(0.04, ((day.max ?? lo) - (day.min ?? lo)) / span))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.dimColor.opacity(0.35))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [theme.accent2Color, theme.accent1Color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * width, height: 6)
                    .offset(x: geo.size.width * start)
            }
        }
        .frame(height: 6)
    }
}

/// Canvas temperature curve with min/max labels, drawn like the web
/// GUI's canvas chart (accent2 line on a dim grid).
struct TemperatureChart: View {
    let points: [WeatherData.HourPoint]
    let theme: ThemePalette

    var body: some View {
        Canvas { context, size in
            let temps = points.compactMap(\.temperature)
            guard temps.count > 1, let lo = temps.min(), let hi = temps.max() else { return }
            let span = max(1, hi - lo)
            let stepX = size.width / CGFloat(points.count - 1)
            func xy(_ i: Int, _ t: Double) -> CGPoint {
                let norm = (t - lo) / span
                return CGPoint(x: CGFloat(i) * stepX,
                               y: size.height - 14 - CGFloat(norm) * (size.height - 28))
            }
            // Grid lines.
            for f in [0.0, 0.5, 1.0] {
                var grid = Path()
                let y = size.height - 14 - CGFloat(f) * (size.height - 28)
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(theme.dimColor.opacity(0.3)), lineWidth: 1)
            }
            // Area fill.
            var area = Path()
            var line = Path()
            for (i, p) in points.enumerated() {
                guard let t = p.temperature else { continue }
                let pt = xy(i, t)
                if i == 0 {
                    area.move(to: CGPoint(x: pt.x, y: size.height - 14))
                    area.addLine(to: pt)
                    line.move(to: pt)
                } else {
                    area.addLine(to: pt)
                    line.addLine(to: pt)
                }
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height - 14))
            area.closeSubpath()
            context.fill(area, with: .color(theme.accent2Color.opacity(0.15)))
            context.stroke(line, with: .color(theme.accent2Color),
                           style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            // Min/max labels.
            let maxText = Text(String(format: "%.0f°", hi))
                .font(Retro.font(9, weight: .bold)).foregroundColor(theme.accent1Color)
            context.draw(context.resolve(maxText), at: CGPoint(x: 14, y: 8), anchor: .leading)
            let minText = Text(String(format: "%.0f°", lo))
                .font(Retro.font(9, weight: .bold)).foregroundColor(theme.accent3Color)
            context.draw(context.resolve(minText), at: CGPoint(x: 14, y: size.height - 6), anchor: .leading)
        }
    }
}

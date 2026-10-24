import SwiftUI

/// Semicircle gauge — the native counterpart of the web GUI's canvas
/// gauges (sunspot / flux / Kp). The filled arc runs from the theme's
/// dim track color through accent2 to accent3 as value rises.
struct GaugeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let value: Double?
    let maxValue: Double
    let label: String
    let display: String

    var body: some View {
        let theme = themeManager.theme
        let fraction = min(1, max(0, (value ?? 0) / maxValue))
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                Canvas { context, size in
                    let lineWidth: CGFloat = 9
                    let radius = (size.width - lineWidth) / 2
                    let center = CGPoint(x: size.width / 2, y: size.height - lineWidth / 2)
                    var track = Path()
                    track.addArc(center: center, radius: radius,
                                 startAngle: .degrees(180), endAngle: .degrees(360),
                                 clockwise: false)
                    context.stroke(track, with: .color(theme.dimColor.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    if fraction > 0 {
                        var arc = Path()
                        arc.addArc(center: center, radius: radius,
                                   startAngle: .degrees(180),
                                   endAngle: .degrees(180 + 180 * fraction),
                                   clockwise: false)
                        let color = fraction > 0.8 ? theme.accent3Color
                            : (fraction > 0.5 ? theme.accent1Color : theme.accent2Color)
                        context.stroke(arc, with: .color(color),
                                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
                .aspectRatio(2, contentMode: .fit)
                Text(display)
                    .font(Retro.font(17, weight: .bold))
                    .foregroundColor(theme.primaryColor)
                    .phosphorGlow(theme, radius: 4)
                    .padding(.bottom, 2)
            }
            Text(label)
                .font(Retro.font(10))
                .foregroundColor(theme.accent2Color)
        }
    }
}

/// Vertical bar chart for the Kp forecast (matches the GUI's Kp bars).
struct KpBarChart: View {
    @EnvironmentObject var themeManager: ThemeManager
    let entries: [(date: String, kp: Double)]

    var body: some View {
        let theme = themeManager.theme
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(entries, id: \.date) { entry in
                VStack(spacing: 3) {
                    Text(String(format: "%.0f", entry.kp))
                        .font(Retro.font(9, weight: .bold))
                        .foregroundColor(theme.primaryColor)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.kp >= 5 ? theme.accent3Color
                              : (entry.kp >= 4 ? theme.accent1Color : theme.accent2Color))
                        .frame(height: max(4, CGFloat(entry.kp) / 9.0 * 64))
                    Text(String(entry.date.suffix(5)))  // MM-DD
                        .font(Retro.font(8))
                        .foregroundColor(theme.dimColor)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 104)
    }
}

/// Moon-phase disc: a lit circle with the shadow terminator drawn as an
/// ellipse whose width follows the phase — the same geometry the
/// Python moon_illumination describes: illum = (1 − cos 2πφ) / 2.
struct MoonDiscView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let phase: Double   // 0 = new, 0.5 = full
    var size: CGFloat = 92

    var body: some View {
        let theme = themeManager.theme
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let circle = Path(ellipseIn: rect.insetBy(dx: 2, dy: 2))
            context.stroke(circle, with: .color(theme.primaryColor.opacity(0.6)), lineWidth: 1)
            context.clip(to: circle)

            let r = (canvasSize.width - 4) / 2
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let litColor = theme.accent2Color
            let darkColor = theme.dimColor.opacity(0.9)
            let waxing = phase < 0.5
            let gibbous = phase > 0.25 && phase < 0.75

            // 1. Dark disc.
            context.fill(circle, with: .color(darkColor))
            // 2. Lit semicircle: right side while waxing, left while waning.
            var half = Path()
            if waxing {
                half.addRect(CGRect(x: cx, y: cy - r, width: r, height: r * 2))
            } else {
                half.addRect(CGRect(x: cx - r, y: cy - r, width: r, height: r * 2))
            }
            context.fill(half, with: .color(litColor))
            // 3. Terminator ellipse, x-radius |cos(2πφ)|·r: painted lit
            //    for gibbous phases (adds the bulge) and dark for
            //    crescents (carves the bite).
            let termRx = abs(cos(2 * Double.pi * phase)) * r
            let termRect = CGRect(x: cx - termRx, y: cy - r,
                                  width: termRx * 2, height: r * 2)
            context.fill(Path(ellipseIn: termRect),
                         with: .color(gibbous ? litColor : darkColor))
        }
        .frame(width: size, height: size)
    }
}

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
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.45, dampingFraction: 0.8),
                               value: value)
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

/// Animated Kp gauge (2.0): a semicircle dial whose fill and needle
/// sweep to the live value on a spring, with a breathing storm halo
/// (TimelineView-driven) whenever Kp reaches storm level (>= 5) —
/// the iOS counterpart of the web GUI's Kp-reactive background.
struct AnimatedKpGaugeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let value: Double?
    let display: String

    @State private var sweep: Double = 0

    private var target: Double { min(1, max(0, (value ?? 0) / 9)) }
    private var storm: Bool { (value ?? 0) >= 5 }

    var body: some View {
        let theme = themeManager.theme
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                if storm {
                    TimelineView(.animation) { timeline in
                        let pulse = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 2.2)
                        Circle()
                            .fill(theme.accent3Color.opacity(0.16 + 0.16 * pulse))
                            .frame(width: 86, height: 86)
                            .blur(radius: 16)
                            .offset(y: 26)
                    }
                }
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
                    if sweep > 0 {
                        var arc = Path()
                        arc.addArc(center: center, radius: radius,
                                   startAngle: .degrees(180),
                                   endAngle: .degrees(180 + 180 * sweep),
                                   clockwise: false)
                        let color = storm ? theme.accent3Color
                            : (sweep > 0.5 ? theme.accent1Color : theme.accent2Color)
                        context.stroke(arc, with: .color(color),
                                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        // needle at the swept angle
                        let a = Double.pi * (1 + sweep)
                        let tip = CGPoint(x: center.x + CGFloat(cos(a)) * (radius - 13),
                                          y: center.y + CGFloat(sin(a)) * (radius - 13))
                        var needle = Path()
                        needle.move(to: center)
                        needle.addLine(to: tip)
                        context.stroke(needle, with: .color(theme.primaryColor),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                .aspectRatio(2, contentMode: .fit)
                Text(display)
                    .font(Retro.font(17, weight: .bold))
                    .foregroundColor(storm ? theme.accent3Color : theme.primaryColor)
                    .phosphorGlow(theme, radius: 4)
                    .padding(.bottom, 2)
                    .contentTransition(.numericText())
            }
            Text("Kp Index")
                .font(Retro.font(10))
                .foregroundColor(theme.accent2Color)
        }
        .onAppear { animateToTarget() }
        .onChange(of: value) { _, _ in animateToTarget() }
    }

    private func animateToTarget() {
        withAnimation(.spring(response: 1.1, dampingFraction: 0.72)) {
            sweep = target
        }
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

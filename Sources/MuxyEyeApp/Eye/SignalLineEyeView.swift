import MuxyEyeCore
import SwiftUI

/// The "signal line" eye: a flat dim line when idle, a scrolling sine when working,
/// and a pulsing orange ring when a session is waiting. Sized by its frame.
struct SignalLineEyeView: View {
    let mode: EyeMode

    var body: some View {
        SignalLineCanvas(
            morph: mode == .waiting ? 1 : 0,
            activity: mode == .idle ? 0 : 1,
            paused: mode == .idle
        )
        .animation(.spring(duration: 0.6), value: mode)
    }
}

private struct SignalLineCanvas: View, Animatable {
    private static let primaryCycle: Double = 1.6
    private static let secondaryCycle: Double = 2.6
    private static let pulseCycle: Double = 1.4
    private static let pulseScale: CGFloat = 0.07
    private static let workingAmplitude: CGFloat = 0.12
    private static let idleOpacity: CGFloat = 0.35
    private static let samples = 48

    /// 0 = line, 1 = ring.
    var morph: CGFloat
    /// 0 = idle (flat and dim), 1 = active.
    var activity: CGFloat
    let paused: Bool

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(morph, activity) }
        set {
            morph = newValue.first
            activity = newValue.second
        }
    }

    var body: some View {
        // 30 fps is smooth for a line this small and halves the CPU cost of a display-rate timeline.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let diameter = min(size.width, size.height)
        guard diameter > 0 else { return }
        context.translateBy(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2)

        let amplitude = Self.workingAmplitude * diameter * activity
        let primaryPhase = -2 * Double.pi * cycleFraction(time, Self.primaryCycle)
        let secondaryPhase = 2 * Double.pi * cycleFraction(time, Self.secondaryCycle)

        let secondaryOpacity = PanelTheme.secondaryLineOpacity * Double(activity * (1 - morph))
        if secondaryOpacity > 0.001 {
            let points = SignalLineGeometry.points(
                diameter: diameter,
                phase: secondaryPhase,
                amplitude: amplitude / 2,
                morph: morph,
                samples: Self.samples
            )
            context.stroke(
                path(through: points),
                with: .color(PanelTheme.secondaryLine.opacity(secondaryOpacity)),
                style: StrokeStyle(lineWidth: diameter * 0.03, lineCap: .round, lineJoin: .round)
            )
        }

        let pulse = 1 + Self.pulseScale * morph * CGFloat(0.5 - 0.5 * cos(2 * Double.pi * cycleFraction(time, Self.pulseCycle)))
        var primary = context
        primary.translateBy(x: diameter / 2, y: diameter / 2)
        primary.scaleBy(x: pulse, y: pulse)
        primary.translateBy(x: -diameter / 2, y: -diameter / 2)
        let points = SignalLineGeometry.points(
            diameter: diameter,
            phase: primaryPhase,
            amplitude: amplitude,
            morph: morph,
            samples: Self.samples
        )
        let opacity = Self.idleOpacity + (1 - Self.idleOpacity) * max(activity, morph)
        primary.stroke(
            path(through: points),
            with: .color(PanelTheme.lineColor(morph: morph).opacity(Double(opacity))),
            style: StrokeStyle(lineWidth: diameter * 0.08, lineCap: .round, lineJoin: .round)
        )
    }

    private func cycleFraction(_ time: Double, _ period: Double) -> Double {
        (time / period).truncatingRemainder(dividingBy: 1)
    }

    private func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

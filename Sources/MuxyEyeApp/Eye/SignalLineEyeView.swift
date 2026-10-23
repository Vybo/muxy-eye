import AppKit
import MuxyEyeCore
import QuartzCore
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
    static let pulseCycle: Double = 1.4
    static let pulseScale: CGFloat = 0.07
    private static let workingAmplitude: CGFloat = 0.12
    private static let idleOpacity: CGFloat = 0.35
    static let samples = 48
    /// The primary line's width as a fraction of the eye's diameter.
    static let lineWidth: CGFloat = 0.08

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
        if !paused, morph >= 0.999 {
            // Once the ring has formed only its pulse moves, and a wait can last hours. Every SwiftUI
            // frame costs a layout pass of the panel, so Core Animation runs the pulse instead.
            PulsingRing()
        } else {
            // 30 fps is smooth for a line this small and halves the CPU cost of a display-rate timeline.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    /// The pulse over one cycle, `fraction` 0…1: a raised cosine from 0 up to 1 and back.
    static func pulseShape(_ fraction: Double) -> CGFloat {
        CGFloat(0.5 - 0.5 * cos(2 * Double.pi * fraction))
    }

    static func cycleFraction(_ time: Double, _ period: Double) -> Double {
        (time / period).truncatingRemainder(dividingBy: 1)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let diameter = min(size.width, size.height)
        guard diameter > 0 else { return }
        context.translateBy(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2)

        let amplitude = Self.workingAmplitude * diameter * activity
        let primaryPhase = -2 * Double.pi * Self.cycleFraction(time, Self.primaryCycle)
        let secondaryPhase = 2 * Double.pi * Self.cycleFraction(time, Self.secondaryCycle)

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

        let pulse = 1 + Self.pulseScale * morph * Self.pulseShape(Self.cycleFraction(time, Self.pulseCycle))
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
            style: StrokeStyle(lineWidth: diameter * Self.lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

/// The settled waiting ring, drawn like the canvas draws it at full morph, pulsing on the same clock
/// so the hand-over from the canvas doesn't jump. The pulse is a Core Animation animation, which runs
/// outside the app.
private struct PulsingRing: NSViewRepresentable {
    func makeNSView(context: Context) -> PulsingRingView { PulsingRingView() }
    func updateNSView(_ view: PulsingRingView, context: Context) {}
}

private final class PulsingRingView: NSView {
    private static let pulseKey = "pulse"
    private static let keyframes = 32

    private let ring = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.fillColor = nil
        ring.strokeColor = NSColor(PanelTheme.waiting).cgColor
        ring.lineCap = .round
        ring.lineJoin = .round
        layer?.addSublayer(ring)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clicks go to the eye around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let diameter = min(bounds.width, bounds.height)
        let inset = CGPoint(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2)
        let points = SignalLineGeometry.points(
            diameter: diameter,
            phase: 0,
            amplitude: 0,
            morph: 1,
            samples: SignalLineCanvas.samples
        )
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.x + inset.x, y: $0.y + inset.y) })
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        ring.path = path
        ring.lineWidth = diameter * SignalLineCanvas.lineWidth
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ring.removeAnimation(forKey: Self.pulseKey)
        guard let window, let host = layer else { return }
        ring.contentsScale = window.backingScaleFactor

        let cycle = SignalLineCanvas.pulseCycle
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = (0...Self.keyframes).map { step in
            1 + SignalLineCanvas.pulseScale * SignalLineCanvas.pulseShape(Double(step) / Double(Self.keyframes))
        }
        animation.duration = cycle
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        // Start mid-cycle, where the canvas's wall-clock pulse is now.
        let phase = SignalLineCanvas.cycleFraction(Date().timeIntervalSinceReferenceDate, cycle) * cycle
        animation.beginTime = host.convertTime(CACurrentMediaTime(), from: nil) - phase
        ring.add(animation, forKey: Self.pulseKey)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window { ring.contentsScale = window.backingScaleFactor }
    }
}

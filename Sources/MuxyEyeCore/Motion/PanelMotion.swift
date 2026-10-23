import CoreGraphics

/// A brief scale bump: up to `scale` over `rise` seconds, back to 1 over `fall`.
public struct Pop: Sendable, Equatable {
    public var scale: CGFloat
    public var rise: Double
    public var fall: Double

    public init(scale: CGFloat, rise: Double, fall: Double) {
        self.scale = scale
        self.rise = rise
        self.fall = fall
    }

    public var totalTime: Double { rise + fall }
}

/// A brief highlight: up to `opacity` over `rise` seconds, gone again after `fall`.
public struct Flash: Sendable, Equatable {
    public var opacity: Double
    public var rise: Double
    public var fall: Double

    public init(opacity: Double, rise: Double, fall: Double) {
        self.opacity = opacity
        self.rise = rise
        self.fall = fall
    }

    public var totalTime: Double { rise + fall }
}

/// The eye's animations, after the approved "island spring" mockup: the eye stretches into the
/// panel with a slight overshoot and the content cascades in; closing fades the content out, then
/// pulls the shape back into the eye without overshoot.
///
/// With Reduce Motion every change is a short plain fade: nothing grows, slides, overshoots or pops,
/// and nothing around a fading view moves. A nil motion means the change happens at once.
public struct PanelMotion: Sendable, Equatable {
    private static let open = MotionCurve.spring(response: 0.5, dampingFraction: 0.72)
    private static let fade = Motion(.easeOut(duration: 0.15))
    private static let rowStagger = 0.05
    private static let staggeredRows = 6

    public var reduceMotion: Bool

    public init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    /// `motion`, or nil under Reduce Motion.
    private func moving(_ motion: Motion) -> Motion? {
        reduceMotion ? nil : motion
    }

    /// The whole panel fading in or out; nil when it stays opaque and its shape does the work.
    public var panelFade: Motion? { reduceMotion ? Self.fade : nil }

    /// The fade a view's insertion or removal runs on its own, so nothing around it moves; nil when
    /// transitions follow the change's own motion.
    public var transitionFade: Motion? { reduceMotion ? Self.fade : nil }

    /// Whether things slide: rows and banners in and out, the selection between rows.
    public var slides: Bool { !reduceMotion }

    // MARK: Shape

    /// The black shape growing from the eye into the panel; nil when it takes the panel's frame at once.
    public var shapeOpen: Motion? { moving(Motion(Self.open)) }

    /// The shape pulling back into the eye. Its delay lets the content fade out first.
    public var shapeClose: Motion? { moving(Motion(.spring(response: 0.38, dampingFraction: 1), delay: 0.08)) }

    // MARK: Content

    /// The whole expanded content fading in, once the shape has mostly grown; nil when it shows at once.
    public var contentIn: Motion? { moving(Motion(.easeOut(duration: 0.2), delay: 0.18)) }

    /// Rail row `index` fading and sliding in. The first rows follow each other; the rest arrive together.
    public func rowIn(_ index: Int) -> Motion? {
        let step = Double(min(max(index, 0), Self.staggeredRows - 1))
        return moving(Motion(.decelerate(duration: 0.35), delay: 0.22 + Self.rowStagger * step))
    }

    /// The detail column fading and sliding in.
    public var detailIn: Motion? { moving(Motion(.decelerate(duration: 0.4), delay: 0.26)) }

    /// The content coming back when the panel reopens while it closes, from however far it had faded.
    public var contentReturn: Motion? { moving(Motion(.easeOut(duration: 0.15))) }

    /// The content fading out when the panel closes; nil when it goes with the panel.
    public var contentOut: Motion? { moving(Motion(.easeOut(duration: 0.12))) }

    /// How far the rows and the detail slide down as they come in.
    public var contentSlide: CGFloat { reduceMotion ? 0 : 6 }

    // MARK: Eye

    /// The signal line and count coming back as the shape lands, or with the panel's fade.
    public var eyeIn: Motion { reduceMotion ? Self.fade : Motion(.easeOut(duration: 0.16), delay: 0.3) }

    /// The signal line and count fading as the shape starts to grow.
    public var eyeOut: Motion { Motion(.easeOut(duration: 0.12)) }

    /// The collapsed eye changing shape: the notch's right wing growing out or retracting, the
    /// count badge appearing or leaving.
    public var collapsedChange: Motion? { moving(Motion(.spring(response: 0.35, dampingFraction: 0.8))) }

    /// The count's bump when it changes; nil for none.
    public var countPop: Pop? { reduceMotion ? nil : Pop(scale: 1.25, rise: 0.09, fall: 0.24) }

    // MARK: Rail

    /// The selection highlight sliding to another row.
    public var selection: Motion? { moving(Motion(.spring(response: 0.32, dampingFraction: 0.86))) }

    /// The detail cross-fading to another session.
    public var detailSwap: Motion? { moving(Motion(.easeInOut(duration: 0.18))) }

    /// Rows arriving, leaving or changing places.
    public var railChange: Motion? { moving(Motion(.spring(response: 0.35, dampingFraction: 0.9))) }

    // MARK: Answering

    /// The option or button the user picked lighting up as the answer goes out. A highlight, not
    /// motion, so it stays with Reduce Motion.
    public var answerFlash: Flash { Flash(opacity: 0.35, rise: 0.04, fall: 0.11) }

    /// The prompt fading out and the next state fading in.
    public var promptSwap: Motion? { moving(Motion(.easeOut(duration: 0.15))) }

    /// An outcome banner arriving under the header, or leaving.
    public var banner: Motion? { moving(Motion(.spring(response: 0.3, dampingFraction: 0.9))) }

    // MARK: Settling

    /// Seconds until the opening shape has settled, so the window can shrink to the panel.
    public var openDuration: Double {
        max(shapeOpen?.totalTime ?? 0, panelFade?.totalTime ?? 0, eyeOut.totalTime)
    }

    /// Seconds until the closing shape has landed on the eye, so the window can shrink to it.
    public var closeDuration: Double {
        max(shapeClose?.totalTime ?? 0, panelFade?.totalTime ?? 0, contentOut?.totalTime ?? 0, eyeIn.totalTime)
    }

    /// Room around the collapsed eye while it changes on its own: the count's pop, the wing's spring.
    public static let eyeMargin: CGFloat = 4

    /// Room around a shape travelling `travel` points with the opening spring, for its overshoot.
    /// Twice the plain overshoot, since a target that moves mid-flight can carry it further.
    public static func overshootMargin(forTravel travel: Double) -> CGFloat {
        max(8, (2 * open.overshoot * travel).rounded(.up))
    }
}

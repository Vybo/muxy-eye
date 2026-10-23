import CoreGraphics

/// The eye's animations, after the approved "island spring" mockup: the eye stretches into the
/// panel with a slight overshoot and the content cascades in; closing fades the content out, then
/// pulls the shape back into the eye without overshoot.
public struct PanelMotion: Sendable, Equatable {
    private static let open = MotionCurve.spring(response: 0.5, dampingFraction: 0.72)
    private static let rowStagger = 0.05
    private static let staggeredRows = 6

    public init() {}

    // MARK: Shape

    /// The black shape growing from the eye into the panel; nil when it takes the panel's frame at once.
    public var shapeOpen: Motion? { Motion(Self.open) }

    /// The shape pulling back into the eye. Its delay lets the content fade out first.
    public var shapeClose: Motion? { Motion(.spring(response: 0.38, dampingFraction: 1), delay: 0.08) }

    // MARK: Content

    /// The whole expanded content fading in, once the shape has mostly grown; nil when it shows at once.
    public var contentIn: Motion? { Motion(.easeOut(duration: 0.2), delay: 0.18) }

    /// Rail row `index` fading and sliding in. The first rows follow each other; the rest arrive together.
    public func rowIn(_ index: Int) -> Motion? {
        let step = Double(min(max(index, 0), Self.staggeredRows - 1))
        return Motion(.decelerate(duration: 0.35), delay: 0.22 + Self.rowStagger * step)
    }

    /// The detail column fading and sliding in.
    public var detailIn: Motion? { Motion(.decelerate(duration: 0.4), delay: 0.26) }

    /// The content fading out when the panel closes; nil when it goes with the panel.
    public var contentOut: Motion? { Motion(.easeOut(duration: 0.12)) }

    /// How far the rows and the detail slide down as they come in.
    public var contentSlide: CGFloat { 6 }

    // MARK: Eye

    /// The signal line and count coming back as the shape lands.
    public var eyeIn: Motion { Motion(.easeOut(duration: 0.16), delay: 0.3) }

    /// The signal line and count fading as the shape starts to grow.
    public var eyeOut: Motion { Motion(.easeOut(duration: 0.12)) }

    // MARK: Rail

    /// The selection highlight sliding to another row.
    public var selection: Motion { Motion(.spring(response: 0.32, dampingFraction: 0.86)) }

    /// The detail cross-fading to another session.
    public var detailSwap: Motion { Motion(.easeInOut(duration: 0.18)) }

    /// Rows arriving, leaving or changing places.
    public var railChange: Motion { Motion(.spring(response: 0.35, dampingFraction: 0.9)) }

    // MARK: Settling

    /// Seconds until the opening shape has settled, so the window can shrink to the panel.
    public var openDuration: Double {
        max(shapeOpen?.totalTime ?? 0, eyeOut.totalTime)
    }

    /// Seconds until the closing shape has landed on the eye, so the window can shrink to it.
    public var closeDuration: Double {
        max(shapeClose?.totalTime ?? 0, contentOut?.totalTime ?? 0, eyeIn.totalTime)
    }

    /// Room around a shape travelling `travel` points with the opening spring, for its overshoot.
    /// Twice the plain overshoot, since a target that moves mid-flight can carry it further.
    public static func overshootMargin(forTravel travel: Double) -> CGFloat {
        max(8, (2 * open.overshoot * travel).rounded(.up))
    }
}

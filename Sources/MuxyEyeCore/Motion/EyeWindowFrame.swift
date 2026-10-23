import CoreGraphics

/// The eye's window frame. At rest it is the footprint of what's visible, so clicks around the eye
/// or the panel pass through to the menu bar and the apps below. While shapes animate it also covers
/// every footprint they move between, grown by a margin for a spring's overshoot, and it shrinks
/// back only once the last animation has finished.
public struct EyeWindowFrame: Sendable, Equatable {
    public private(set) var footprint: CGRect
    /// When the last running animation is done; nil at rest.
    public private(set) var settlesAt: ContinuousClock.Instant?
    /// Every footprint since the window was last at rest.
    private var span: CGRect?

    public init(footprint: CGRect) {
        self.footprint = footprint
    }

    public var isMoving: Bool { span != nil }

    /// The footprint changes with nothing animating towards it. While other animations run, the
    /// window keeps covering where they move.
    public mutating func jump(to footprint: CGRect) {
        if let span { self.span = span.union(footprint) }
        self.footprint = footprint
    }

    /// Shapes start animating towards `footprint` at `now`, for `duration`.
    public mutating func animate(to footprint: CGRect, at now: ContinuousClock.Instant, for duration: Duration) {
        span = (span ?? self.footprint).union(footprint)
        self.footprint = footprint
        let end = now + duration
        settlesAt = settlesAt.map { max($0, end) } ?? end
    }

    /// Comes to rest once every animation is done. Returns whether it did, so the window can shrink.
    @discardableResult
    public mutating func settle(at now: ContinuousClock.Instant) -> Bool {
        guard let settlesAt, now >= settlesAt else { return false }
        span = nil
        self.settlesAt = nil
        return true
    }

    /// The window frame: the footprint at rest; while moving, everything moved across plus `margin`
    /// on each side, kept within `bounds` (whose top is the top of the screen).
    public func frame(margin: CGFloat, within bounds: CGRect) -> CGRect {
        guard let span else { return footprint }
        let grown = span.insetBy(dx: -margin, dy: -margin).intersection(bounds)
        return grown.isNull ? span : grown
    }
}

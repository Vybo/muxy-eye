import CoreGraphics

extension EyeOutline {
    /// How far `point`, in screen coordinates, is from the outline's shape, in points; 0 inside. The
    /// corners are circular arcs, as in `contains`.
    public func distance(to point: CGPoint) -> CGFloat {
        let rect = frame.standardized
        let limit = max(0, min(rect.width, rect.height) / 2)
        let radius = min(max(point.y >= rect.midY ? topRadius : bottomRadius, 0), limit)
        // The outline is this inner rectangle grown by the radius all round.
        let inner = rect.insetBy(dx: radius, dy: radius)
        let dx = max(inner.minX - point.x, 0, point.x - inner.maxX)
        let dy = max(inner.minY - point.y, 0, point.y - inner.maxY)
        return max(0, (dx * dx + dy * dy).squareRoot() - radius)
    }
}

/// Where the eye's window lets clicks through to what is below it. At rest the window is the box
/// around what shows; where that box holds room beside the shapes (an eye beside the open panel,
/// the corners around a large eye, the space around its count), a click there belongs to the menu
/// bar, the Dock or the app below, not to the eye.
public enum ClickThrough {
    /// How far part of the window must be from every shape to count as room that lets clicks
    /// through. The corners around the usual eye and the notch's rounded corners (at most 5 pt deep)
    /// stay the eye's, as they always were.
    public static let depth: CGFloat = 5
    /// How finely `hasGap` looks for such room, in points.
    static let step: CGFloat = 2

    /// Whether a click at `point` lands on one of `outlines`.
    public static func hits(_ point: CGPoint, _ outlines: [EyeOutline]) -> Bool {
        outlines.contains { $0.contains(point) }
    }

    /// Whether `window` holds room deeper than `depth` outside all of `outlines`. It looks across the
    /// window every `step` points, edges and corners included, where the room around a circle is
    /// deepest.
    public static func hasGap(in window: CGRect, around outlines: [EyeOutline]) -> Bool {
        let window = window.standardized
        guard !window.isNull, window.width > 0, window.height > 0 else { return false }
        // The open panel at its default spot: one square-cornered shape covers the whole window.
        if outlines.contains(where: { $0.topRadius <= 0 && $0.bottomRadius <= 0 && $0.frame.contains(window) }) {
            return false
        }
        func samples(from low: CGFloat, to high: CGFloat) -> [CGFloat] {
            Array(stride(from: low, to: high, by: step)) + [high]
        }
        let columns = samples(from: window.minX, to: window.maxX)
        for y in samples(from: window.minY, to: window.maxY) {
            for x in columns {
                let point = CGPoint(x: x, y: y)
                if outlines.allSatisfy({ $0.distance(to: point) > depth }) { return true }
            }
        }
        return false
    }
}

extension EyeLayout {
    /// The shapes that take clicks at rest, on screen. Collapsed (`expanded` nil): the eye's shape and
    /// its count. Open: the whole panel, whose rounded corners close it as they always did, the eye's
    /// shape, and its count where the panel leaves the eye uncovered and the count shows.
    public static func clickOutlines(_ collapsed: CollapsedLayout, expanded: CGRect?) -> [EyeOutline] {
        guard let expanded else { return grabOutlines(collapsed) }
        var outlines = [
            EyeOutline(frame: expanded, topRadius: 0, bottomRadius: 0),
            collapsedOutline(collapsed)
        ]
        if !panel(expanded, covers: collapsed), let count = countOutline(collapsed) {
            outlines.append(count)
        }
        return outlines
    }
}

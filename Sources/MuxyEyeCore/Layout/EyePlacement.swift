import CoreGraphics
import Foundation

/// Where the expanded panel opens relative to the eye.
public enum PanelSide: String, Sendable, CaseIterable {
    case below, above, left, right

    /// Where the panel opens when this side has no room for it.
    public var opposite: PanelSide {
        switch self {
        case .below: .above
        case .above: .below
        case .left: .right
        case .right: .left
        }
    }
}

/// Where the user put the collapsed eye and how large they made it. Until they move or resize it,
/// the eye sits at its default spot, at the top centre in the notch or the menu bar, at its usual size.
public struct EyePlacement: Sendable, Equatable {
    /// How small and how large the eye can get, as multiples of its usual size.
    public static let scales: ClosedRange<CGFloat> = 0.5...3
    /// A mouse wheel scrolls by lines; one line resizes the eye as much as this many points of
    /// trackpad scrolling.
    public static let pointsPerLine: CGFloat = 20
    /// How much one point of scrolling resizes the eye, as the natural log of the factor. Resizing
    /// multiplies, so each step looks the same at every size and scrolling back undoes it exactly.
    static let growthPerPoint: CGFloat = 0.005

    public static let standard = EyePlacement()

    /// The eye's centre as fractions of its screen's width and height, from the screen's bottom-left
    /// corner (y up, as screen coordinates are), so it sits at the same relative place on every
    /// display; nil at the default spot.
    public var position: CGPoint?
    /// The eye's size as a multiple of its usual size on each display.
    public var scale: CGFloat

    public init(position: CGPoint? = nil, scale: CGFloat = 1) {
        self.position = position
        self.scale = scale
    }

    /// Moved or resized: the eye is then a free circle with its count beside it, and the eye's menu
    /// offers to put it back.
    public var isCustomized: Bool { position != nil || scale != 1 }

    /// The placement with what can't be shown brought back: a position on the screen, a size within
    /// `scales`, and the default for anything that isn't a number.
    public var sanitized: EyePlacement {
        var placement = self
        if let position {
            placement.position = position.x.isFinite && position.y.isFinite
                ? CGPoint(x: min(max(position.x, 0), 1), y: min(max(position.y, 0), 1))
                : nil
        }
        placement.scale = scale.isFinite ? Self.clampedScale(scale) : 1
        return placement
    }

    /// The placement after scrolling `delta` over the eye: points when `precise` (a trackpad),
    /// otherwise lines (a mouse wheel). Scrolling up (fingers or wheel moving away from you) grows the
    /// eye; `inverted` is natural scrolling's flip of the delta, undone so the same movement always
    /// grows it.
    public func resized(byScroll delta: CGFloat, precise: Bool, inverted: Bool) -> EyePlacement {
        let points = (precise ? delta : delta * Self.pointsPerLine) * (inverted ? -1 : 1)
        guard points != 0, points.isFinite else { return self }
        var placement = self
        placement.scale = Self.clampedScale(scale * exp(points * Self.growthPerPoint))
        return placement
    }

    private static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, scales.lowerBound), scales.upperBound)
    }
}

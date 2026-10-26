import CoreGraphics

/// A press on the collapsed eye. It is a click until the pointer has moved `threshold` points from
/// where it went down; from then on it is a drag that moves the eye with the pointer, even if the
/// pointer comes back, and releasing it drops the eye there instead of opening the panel.
public struct EyeDrag: Sendable, Equatable {
    public enum Release: Sendable, Equatable {
        /// Open the panel.
        case click
        /// Leave the eye with its centre here.
        case drop(CGPoint)
    }

    /// How far the pointer moves, in points, before a press becomes a drag.
    public static let threshold: CGFloat = 4

    /// Where the press went down, in screen coordinates.
    public let start: CGPoint
    /// Where the eye's centre was then.
    public let eyeCenter: CGPoint
    public private(set) var isDragging = false

    public init(start: CGPoint, eyeCenter: CGPoint) {
        self.start = start
        self.eyeCenter = eyeCenter
    }

    /// The pointer moved to `point`. Returns where the eye's centre goes once the press is a drag;
    /// nil while it is still a click.
    public mutating func move(to point: CGPoint) -> CGPoint? {
        if !isDragging, movesFarEnough(to: point) { isDragging = true }
        return isDragging ? center(at: point) : nil
    }

    /// The button went up at `point`.
    public func release(at point: CGPoint) -> Release {
        isDragging || movesFarEnough(to: point) ? .drop(center(at: point)) : .click
    }

    private func movesFarEnough(to point: CGPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) >= Self.threshold
    }

    /// The eye keeps the offset from the pointer it had when it was grabbed.
    private func center(at point: CGPoint) -> CGPoint {
        CGPoint(x: eyeCenter.x + point.x - start.x, y: eyeCenter.y + point.y - start.y)
    }
}

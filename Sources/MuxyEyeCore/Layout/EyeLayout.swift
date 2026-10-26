import CoreGraphics

public struct ScreenGeometry: Sendable, Equatable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeftWidth: CGFloat?
    public var auxiliaryTopRightWidth: CGFloat?

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
    }

    public var hasNotch: Bool { safeAreaTop > 0 }

    var notchMinX: CGFloat { frame.minX + (auxiliaryTopLeftWidth ?? 0) }
    var notchMaxX: CGFloat { frame.maxX - (auxiliaryTopRightWidth ?? 0) }
}

/// `panelFrame` is in screen coordinates; the other frames are relative to the panel's bottom-left corner.
public struct CollapsedLayout: Sendable, Equatable {
    public var panelFrame: CGRect
    public var eyeFrame: CGRect
    public var countFrame: CGRect?
    public var shapeFrame: CGRect?

    public init(panelFrame: CGRect, eyeFrame: CGRect, countFrame: CGRect?, shapeFrame: CGRect?) {
        self.panelFrame = panelFrame
        self.eyeFrame = eyeFrame
        self.countFrame = countFrame
        self.shapeFrame = shapeFrame
    }

    /// One of the layout's frames, which are relative to the panel, in screen coordinates.
    public func onScreen(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: panelFrame.minX, dy: panelFrame.minY)
    }
}

/// The outline of one of the eye's black shapes: a frame on screen, square or rounded on top,
/// rounded below. The shapes morph between these.
public struct EyeOutline: Sendable, Equatable {
    public var frame: CGRect
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(frame: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) {
        self.frame = frame
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// Whether `point`, in screen coordinates (y up, so the top corners are at `maxY`), is inside
    /// the outline. The corners are taken as circular arcs. The drawn shape uses continuous corners,
    /// which differ by at most 0.5 pt at these radii (measured: 0.48 pt for the panel's 22 pt
    /// corners, 0.25 pt for the notch's 10 pt, 0.23 pt for the eye's circle), well below what a
    /// click can tell apart.
    public func contains(_ point: CGPoint) -> Bool {
        let rect = frame.standardized
        guard point.x >= rect.minX, point.x <= rect.maxX, point.y >= rect.minY, point.y <= rect.maxY else {
            return false
        }
        let limit = max(0, min(rect.width, rect.height) / 2)
        let upper = point.y >= rect.midY
        let radius = min(max(upper ? topRadius : bottomRadius, 0), limit)
        guard radius > 0 else { return true }
        // The nearest point of the outline's inner rectangle, inset by the radius at the corners.
        let centerX = min(max(point.x, rect.minX + radius), rect.maxX - radius)
        let centerY = upper ? min(point.y, rect.maxY - radius) : max(point.y, rect.minY + radius)
        let dx = point.x - centerX
        let dy = point.y - centerY
        return dx * dx + dy * dy <= radius * radius
    }
}

public enum EyeLayout {
    public static let wingWidth: CGFloat = 34
    public static let panelWidth: CGFloat = 640
    public static let badgeSize = CGSize(width: 18, height: 16)
    public static let notchCornerRadius: CGFloat = 10
    public static let panelCornerRadius: CGFloat = 22

    static let badgeGap: CGFloat = 4
    static let fallbackMenuBarHeight: CGFloat = 24

    public static func collapsed(on screen: ScreenGeometry, waitingCount: Int) -> CollapsedLayout {
        screen.hasNotch ? notchLayout(screen, waitingCount: waitingCount) : plainLayout(screen, waitingCount: waitingCount)
    }

    public static func expandedFrame(on screen: ScreenGeometry, contentHeight: CGFloat) -> CGRect {
        let centerX = screen.hasNotch ? (screen.notchMinX + screen.notchMaxX) / 2 : screen.frame.midX
        let height = min(contentHeight, screen.visibleFrame.height * 3 / 5)
        return CGRect(x: centerX - panelWidth / 2, y: screen.frame.maxY - height, width: panelWidth, height: height)
    }

    /// The collapsed eye's black shape: the widened notch, square on top, or the eye's circle.
    public static func collapsedOutline(_ layout: CollapsedLayout) -> EyeOutline {
        if let shape = layout.shapeFrame {
            return EyeOutline(frame: layout.onScreen(shape), topRadius: 0, bottomRadius: notchCornerRadius)
        }
        let eye = layout.onScreen(layout.eyeFrame)
        let radius = min(eye.width, eye.height) / 2
        return EyeOutline(frame: eye, topRadius: radius, bottomRadius: radius)
    }

    /// The expanded panel's black shape: square on top, rounded below.
    public static func expandedOutline(_ frame: CGRect) -> EyeOutline {
        EyeOutline(frame: frame, topRadius: 0, bottomRadius: panelCornerRadius)
    }

    /// Room around a moving shape for its overshoot, enough for the tallest panel on `screen`.
    public static func motionMargin(on screen: ScreenGeometry) -> CGFloat {
        let tallest = expandedFrame(on: screen, contentHeight: .greatestFiniteMagnitude)
        return PanelMotion.overshootMargin(forTravel: max(tallest.height, tallest.width / 2))
    }

    /// Everything the eye can draw on `screen`, in screen coordinates: the tallest panel, the eye with
    /// and without its count, and the motion margin around them, from the top of the screen down.
    public static func stageFrame(on screen: ScreenGeometry) -> CGRect {
        let margin = motionMargin(on: screen)
        let shapes = expandedFrame(on: screen, contentHeight: .greatestFiniteMagnitude)
            .union(collapsed(on: screen, waitingCount: 0).panelFrame)
            .union(collapsed(on: screen, waitingCount: 2).panelFrame)
            .insetBy(dx: -margin, dy: -margin)
        return CGRect(x: shapes.minX, y: shapes.minY, width: shapes.width, height: screen.frame.maxY - shapes.minY)
    }

    /// `rect`, in screen coordinates, measured from the top left of `stage` with y growing down,
    /// as the stage's view lays it out.
    public static func stageRect(_ rect: CGRect, in stage: CGRect) -> CGRect {
        CGRect(x: rect.minX - stage.minX, y: stage.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func plainLayout(_ screen: ScreenGeometry, waitingCount: Int) -> CollapsedLayout {
        let measured = screen.frame.maxY - screen.visibleFrame.maxY
        let menuBarHeight = measured > 0 ? measured : fallbackMenuBarHeight
        let diameter = max(18, menuBarHeight - 4)
        let eye = CGRect(
            x: screen.frame.midX - diameter / 2,
            y: screen.frame.maxY - menuBarHeight + (menuBarHeight - diameter) / 2,
            width: diameter,
            height: diameter)
        var panel = eye
        var badge: CGRect?
        if waitingCount >= 2 {
            let rect = CGRect(
                x: eye.maxX + badgeGap,
                y: eye.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height)
            panel = eye.union(rect)
            badge = rect
        }
        return CollapsedLayout(
            panelFrame: panel,
            eyeFrame: eye.offsetBy(dx: -panel.minX, dy: -panel.minY),
            countFrame: badge?.offsetBy(dx: -panel.minX, dy: -panel.minY),
            shapeFrame: nil)
    }

    private static func notchLayout(_ screen: ScreenGeometry, waitingCount: Int) -> CollapsedLayout {
        let height = screen.safeAreaTop
        let minX = screen.notchMinX - wingWidth
        let maxX = screen.notchMaxX + (waitingCount >= 1 ? wingWidth : 0)
        let panel = CGRect(x: minX, y: screen.frame.maxY - height, width: maxX - minX, height: height)
        let diameter = height - 8
        let eye = CGRect(
            x: (wingWidth - diameter) / 2,
            y: (height - diameter) / 2,
            width: diameter,
            height: diameter)
        var count: CGRect?
        if waitingCount >= 1 {
            let rightWingMinX = screen.notchMaxX - minX
            count = CGRect(
                x: rightWingMinX + (wingWidth - badgeSize.width) / 2,
                y: (height - badgeSize.height) / 2,
                width: badgeSize.width,
                height: badgeSize.height)
        }
        return CollapsedLayout(
            panelFrame: panel,
            eyeFrame: eye,
            countFrame: count,
            shapeFrame: CGRect(origin: .zero, size: panel.size))
    }
}

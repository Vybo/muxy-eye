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
}

public enum EyeLayout {
    public static let wingWidth: CGFloat = 34
    public static let panelWidth: CGFloat = 640
    public static let badgeSize = CGSize(width: 18, height: 16)

    private static let badgeGap: CGFloat = 4
    private static let fallbackMenuBarHeight: CGFloat = 24

    public static func collapsed(on screen: ScreenGeometry, waitingCount: Int) -> CollapsedLayout {
        screen.hasNotch ? notchLayout(screen, waitingCount: waitingCount) : plainLayout(screen, waitingCount: waitingCount)
    }

    public static func expandedFrame(on screen: ScreenGeometry, contentHeight: CGFloat) -> CGRect {
        let centerX = screen.hasNotch ? (screen.notchMinX + screen.notchMaxX) / 2 : screen.frame.midX
        let height = min(contentHeight, screen.visibleFrame.height * 3 / 5)
        return CGRect(x: centerX - panelWidth / 2, y: screen.frame.maxY - height, width: panelWidth, height: height)
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

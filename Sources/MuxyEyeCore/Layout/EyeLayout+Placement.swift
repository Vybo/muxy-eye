import CoreGraphics

extension CollapsedLayout {
    /// Whether `other` is this layout moved somewhere else: the same shapes at the same sizes and
    /// offsets, so only its place on screen differs.
    public func isSameShape(as other: CollapsedLayout) -> Bool {
        func same(_ a: CGRect?, _ b: CGRect?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?):
                abs(a.minX - b.minX) < Self.tolerance && abs(a.minY - b.minY) < Self.tolerance
                    && abs(a.width - b.width) < Self.tolerance && abs(a.height - b.height) < Self.tolerance
            default: false
            }
        }
        return same(CGRect(origin: .zero, size: panelFrame.size), CGRect(origin: .zero, size: other.panelFrame.size))
            && same(eyeFrame, other.eyeFrame) && same(countFrame, other.countFrame) && same(shapeFrame, other.shapeFrame)
    }

    private static let tolerance: CGFloat = 0.001
}

/// The eye once the user moved or resized it, and the panel on the side they chose. At the default
/// spot and size, with the panel below, everything is laid out exactly as by the functions without
/// a placement.
extension EyeLayout {
    /// The collapsed eye where `placement` puts it. A moved or resized eye is a free circle, kept on
    /// the screen and out of the notch, with the count beside it from two waiting sessions on.
    public static func collapsed(on screen: ScreenGeometry, waitingCount: Int, placement: EyePlacement) -> CollapsedLayout {
        guard placement.isCustomized else { return collapsed(on: screen, waitingCount: waitingCount) }
        return freeLayout(screen, waitingCount: waitingCount, placement: placement)
    }

    /// The centre of the layout's eye, on screen.
    public static func eyeCenter(of layout: CollapsedLayout) -> CGPoint {
        let eye = layout.onScreen(layout.eyeFrame)
        return CGPoint(x: eye.midX, y: eye.midY)
    }

    /// `center`, on screen, as fractions of `screen`'s width and height: the placement's position.
    public static func position(of center: CGPoint, on screen: ScreenGeometry) -> CGPoint {
        let frame = screen.frame
        guard frame.width > 0, frame.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (center.x - frame.minX) / frame.width, y: (center.y - frame.minY) / frame.height)
    }

    /// What a press can grab the collapsed eye by, on screen: its black shape and the count's capsule.
    public static func grabOutlines(_ layout: CollapsedLayout) -> [EyeOutline] {
        var outlines = [collapsedOutline(layout)]
        if let count = layout.countFrame {
            let badge = layout.onScreen(count)
            outlines.append(EyeOutline(frame: badge, topRadius: badge.height / 2, bottomRadius: badge.height / 2))
        }
        return outlines
    }

    // MARK: Panel

    /// The side the panel opens on: `side` when the panel has room there, else the opposite side if
    /// that has room, else `side` anyway, where the panel is then kept on screen.
    public static func openingSide(
        _ side: PanelSide,
        on screen: ScreenGeometry,
        collapsed: CollapsedLayout,
        placement: EyePlacement,
        contentHeight: CGFloat
    ) -> PanelSide {
        func fits(_ side: PanelSide) -> Bool {
            hasRoom(on: side, screen, collapsed: collapsed, placement: placement, contentHeight: contentHeight)
        }
        if fits(side) { return side }
        return fits(side.opposite) ? side.opposite : side
    }

    /// The panel on `side` of the eye. It grows out of the eye: the edge facing away from `side`
    /// lines up with the eye's, and the panel is centred on the eye along that edge. It stays inside
    /// the visible frame, clear of the menu bar, the Dock and the notch. Below an eye in the menu bar
    /// it hangs from the top of the screen instead, as it always did: at the default spot exactly as
    /// before, elsewhere centred on the eye.
    public static func expandedFrame(
        on screen: ScreenGeometry,
        contentHeight: CGFloat,
        collapsed: CollapsedLayout,
        placement: EyePlacement,
        side: PanelSide
    ) -> CGRect {
        let eye = collapsed.onScreen(collapsed.eyeFrame)
        if hangsFromTop(on: screen, collapsed: collapsed, placement: placement, side: side) {
            let hanging = expandedFrame(on: screen, contentHeight: contentHeight)
            guard placement.isCustomized else { return hanging }
            let bounds = screen.visibleFrame
            let x = max(bounds.minX, min(eye.midX - hanging.width / 2, bounds.maxX - hanging.width))
            return CGRect(x: x, y: hanging.minY, width: hanging.width, height: hanging.height)
        }
        let size = panelSize(on: screen, contentHeight: contentHeight)
        let origin = switch side {
        case .below: CGPoint(x: eye.midX - size.width / 2, y: eye.maxY - size.height)
        case .above: CGPoint(x: eye.midX - size.width / 2, y: eye.minY)
        case .left: CGPoint(x: eye.maxX - size.width, y: eye.midY - size.height / 2)
        case .right: CGPoint(x: eye.minX, y: eye.midY - size.height / 2)
        }
        return clamp(CGRect(origin: origin, size: size), into: panelBounds(on: screen))
    }

    /// Whether the panel on `side` hangs from the top of the screen, as it always did: below the eye
    /// at its default spot, or below an eye anywhere in the menu bar (the notch's height on a notch
    /// display), at any size.
    public static func hangsFromTop(
        on screen: ScreenGeometry,
        collapsed: CollapsedLayout,
        placement: EyePlacement,
        side: PanelSide
    ) -> Bool {
        guard side == .below else { return false }
        guard placement.isCustomized else { return true }
        let eye = collapsed.onScreen(collapsed.eyeFrame)
        return eye.maxY - (screen.frame.maxY - topBandHeight(on: screen)) > edgeTolerance
    }

    /// Room left at the top of the panel for the physical notch: only a panel hanging from the top
    /// of the screen reaches it.
    public static func topInset(
        on screen: ScreenGeometry,
        collapsed: CollapsedLayout,
        placement: EyePlacement,
        side: PanelSide
    ) -> CGFloat {
        let hangs = hangsFromTop(on: screen, collapsed: collapsed, placement: placement, side: side)
        return hangs && screen.hasNotch ? screen.safeAreaTop : 0
    }

    /// The panel's black shape: square on top where it hangs from the top of the screen, rounded
    /// everywhere else.
    public static func expandedOutline(_ frame: CGRect, on screen: ScreenGeometry) -> EyeOutline {
        // The hanging panel's top is computed from its height, so it can miss the screen's top by a hair.
        let hangs = frame.maxY >= screen.frame.maxY - edgeTolerance
        return EyeOutline(frame: frame, topRadius: hangs ? 0 : panelCornerRadius, bottomRadius: panelCornerRadius)
    }

    /// Whether the panel at `frame` covers the layout's eye, which then fades into it. An eye beside
    /// the panel, in the menu bar above it for one, stays as it is.
    public static func panel(_ frame: CGRect, covers layout: CollapsedLayout) -> Bool {
        overlaps(frame, layout.onScreen(layout.eyeFrame))
    }

    // MARK: Stage

    /// Everything the eye can draw on `screen` with this placement, in screen coordinates: the eye
    /// with and without its count, the tallest panel on the chosen side and on the opposite one, and
    /// the motion margin around them, within the screen.
    public static func stageFrame(on screen: ScreenGeometry, placement: EyePlacement, side: PanelSide) -> CGRect {
        if opensFromTheTop(placement, side) { return stageFrame(on: screen) }
        let margin = motionMargin(on: screen, placement: placement, side: side)
        let alone = collapsed(on: screen, waitingCount: 0, placement: placement)
        var shapes = alone.panelFrame.union(collapsed(on: screen, waitingCount: 2, placement: placement).panelFrame)
        for candidate in [side, side.opposite] {
            shapes = shapes.union(expandedFrame(
                on: screen,
                contentHeight: .greatestFiniteMagnitude,
                collapsed: alone,
                placement: placement,
                side: candidate))
        }
        return shapes.insetBy(dx: -margin, dy: -margin).intersection(screen.frame)
    }

    /// Room around a moving shape for its overshoot. A free panel can grow out of the eye across its
    /// whole width, not just half of it.
    public static func motionMargin(on screen: ScreenGeometry, placement: EyePlacement, side: PanelSide) -> CGFloat {
        if opensFromTheTop(placement, side) { return motionMargin(on: screen) }
        let tallest = panelSize(on: screen, contentHeight: .greatestFiniteMagnitude)
        return PanelMotion.overshootMargin(forTravel: max(tallest.width, tallest.height))
    }

    // MARK: Helpers

    /// Closer than this, in points, two edges count as one.
    private static let edgeTolerance: CGFloat = 0.5

    /// The eye at its default spot with the panel below: the stage and the margins are exactly as before.
    private static func opensFromTheTop(_ placement: EyePlacement, _ side: PanelSide) -> Bool {
        !placement.isCustomized && side == .below
    }

    /// The band at the top of the screen that the menu bar, or the notch, takes.
    private static func topBandHeight(on screen: ScreenGeometry) -> CGFloat {
        let measured = screen.frame.maxY - screen.visibleFrame.maxY
        return max(screen.safeAreaTop, measured > 0 ? measured : fallbackMenuBarHeight)
    }

    private static func panelSize(on screen: ScreenGeometry, contentHeight: CGFloat) -> CGSize {
        CGSize(width: panelWidth, height: min(contentHeight, screen.visibleFrame.height * 3 / 5))
    }

    /// Where a free panel may go: the visible frame, below the notch even with the menu bar hidden.
    private static func panelBounds(on screen: ScreenGeometry) -> CGRect {
        var bounds = screen.visibleFrame
        if screen.hasNotch {
            bounds.size.height = max(0, min(bounds.maxY, screen.frame.maxY - screen.safeAreaTop) - bounds.minY)
        }
        return bounds
    }

    private static func hasRoom(
        on side: PanelSide,
        _ screen: ScreenGeometry,
        collapsed: CollapsedLayout,
        placement: EyePlacement,
        contentHeight: CGFloat
    ) -> Bool {
        if hangsFromTop(on: screen, collapsed: collapsed, placement: placement, side: side) { return true }
        let bounds = panelBounds(on: screen)
        let size = panelSize(on: screen, contentHeight: contentHeight)
        let eye = collapsed.onScreen(collapsed.eyeFrame)
        return switch side {
        case .below: eye.maxY - size.height >= bounds.minY
        case .above: eye.minY + size.height <= bounds.maxY
        case .left: eye.maxX - size.width >= bounds.minX
        case .right: eye.minX + size.width <= bounds.maxX
        }
    }

    private static func freeLayout(_ screen: ScreenGeometry, waitingCount: Int, placement: EyePlacement) -> CollapsedLayout {
        // The usual eye on this screen gives the size to scale, and the spot when it was only resized.
        let usual = collapsed(on: screen, waitingCount: 0)
        let usualEye = usual.onScreen(usual.eyeFrame)
        let scale = placement.scale
        let diameter = usualEye.width * scale
        let frame = screen.frame
        let center = placement.position.map {
            CGPoint(x: frame.minX + $0.x * frame.width, y: frame.minY + $0.y * frame.height)
        } ?? CGPoint(x: usualEye.midX, y: usualEye.midY)
        let placed = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        let eye = avoidingNotch(clamp(placed, into: frame), on: screen)

        var panel = eye
        var badge: CGRect?
        if waitingCount >= 2 {
            let size = CGSize(width: badgeSize.width * scale, height: badgeSize.height * scale)
            let gap = badgeGap * scale
            let y = eye.midY - size.height / 2
            let right = CGRect(origin: CGPoint(x: eye.maxX + gap, y: y), size: size)
            let left = CGRect(origin: CGPoint(x: eye.minX - gap - size.width, y: y), size: size)
            let behindNotch = notchRect(on: screen).map { overlaps(right, $0) } ?? false
            let rect = frame.contains(right) && !behindNotch ? right : left
            panel = eye.union(rect)
            badge = rect
        }
        return CollapsedLayout(
            panelFrame: panel,
            eyeFrame: eye.offsetBy(dx: -panel.minX, dy: -panel.minY),
            countFrame: badge?.offsetBy(dx: -panel.minX, dy: -panel.minY),
            shapeFrame: nil)
    }

    /// The notch's cut-out, on screen; nil without a notch.
    private static func notchRect(on screen: ScreenGeometry) -> CGRect? {
        guard screen.hasNotch else { return nil }
        return CGRect(
            x: screen.notchMinX,
            y: screen.frame.maxY - screen.safeAreaTop,
            width: screen.notchMaxX - screen.notchMinX,
            height: screen.safeAreaTop)
    }

    /// `eye` moved out from behind the notch the shortest way that stays on screen: to its left,
    /// to its right, or down below it.
    private static func avoidingNotch(_ eye: CGRect, on screen: ScreenGeometry) -> CGRect {
        guard let notch = notchRect(on: screen), overlaps(eye, notch) else { return eye }
        var left = eye
        left.origin.x = notch.minX - eye.width
        var right = eye
        right.origin.x = notch.maxX
        var below = eye
        below.origin.y = notch.minY - eye.height
        let candidates = [left, right, below].filter { screen.frame.contains($0) }
        func distance(_ rect: CGRect) -> CGFloat { abs(rect.minX - eye.minX) + abs(rect.minY - eye.minY) }
        return candidates.min { distance($0) < distance($1) } ?? below
    }

    /// Whether `a` and `b` share some area; touching edges don't count.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = a.intersection(b)
        return !shared.isNull && shared.width > 0 && shared.height > 0
    }

    /// `rect` moved, not resized, to lie inside `bounds`; along an axis where it doesn't fit, it
    /// starts at the bounds' start.
    private static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var rect = rect
        rect.origin.x = max(bounds.minX, min(rect.minX, bounds.maxX - rect.width))
        rect.origin.y = max(bounds.minY, min(rect.minY, bounds.maxY - rect.height))
        return rect
    }
}

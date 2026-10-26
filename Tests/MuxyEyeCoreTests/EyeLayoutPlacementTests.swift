import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct EyeLayoutPlacementTests {
    let ultrawide = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
        visibleFrame: CGRect(x: 0, y: 0, width: 3440, height: 1415),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
    /// Notch from x 662 to 850, 32 pt tall.
    let mbp14 = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662)
    /// A display left of and above the main one.
    let external = ScreenGeometry(
        frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1055),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
    /// A display far below the main one, where the panel's computed top lands a hair below the
    /// screen's top.
    let lowered = ScreenGeometry(
        frame: CGRect(x: 0, y: -2632.75, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: -2632.75, width: 1512, height: 958),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)

    let middle = EyePlacement(position: CGPoint(x: 0.5, y: 0.5))
    let quarter = EyePlacement(position: CGPoint(x: 0.25, y: 0.5))

    private var screens: [ScreenGeometry] { [ultrawide, mbp14, external] }

    private func eye(_ layout: CollapsedLayout) -> CGRect { layout.onScreen(layout.eyeFrame) }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    // MARK: The collapsed eye

    @Test func theDefaultSpotAndSizeLookExactlyAsBefore() {
        for screen in screens {
            for count in 0...3 {
                #expect(
                    EyeLayout.collapsed(on: screen, waitingCount: count, placement: .standard)
                        == EyeLayout.collapsed(on: screen, waitingCount: count))
            }
        }
    }

    @Test func aMovedEyeIsACircleAtTheSameRelativeSpotOnEveryDisplay() {
        let wide = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: quarter)
        #expect(eye(wide) == CGRect(x: 849.5, y: 709.5, width: 21, height: 21))
        #expect(wide.shapeFrame == nil)
        #expect(EyeLayout.collapsedOutline(wide).topRadius == 10.5)

        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 1, placement: quarter)
        #expect(eye(notch) == CGRect(x: 366, y: 479, width: 24, height: 24))
        #expect(notch.shapeFrame == nil)
        #expect(notch.countFrame == nil)
        #expect(EyeLayout.collapsedOutline(notch).frame == eye(notch))

        let side = EyeLayout.collapsed(on: external, waitingCount: 0, placement: quarter)
        #expect(EyeLayout.eyeCenter(of: side) == CGPoint(x: -1440, y: 740))
    }

    @Test func aMovedEyeShowsItsCountBesideItFromTwoOnEveryDisplay() throws {
        for screen in screens {
            #expect(EyeLayout.collapsed(on: screen, waitingCount: 1, placement: quarter).countFrame == nil)
            let layout = EyeLayout.collapsed(on: screen, waitingCount: 2, placement: quarter)
            let count = layout.onScreen(try #require(layout.countFrame))
            #expect(count.minX == eye(layout).maxX + 4)
            #expect(count.midY == eye(layout).midY)
            #expect(count.size == EyeLayout.badgeSize)
            #expect(layout.panelFrame == eye(layout).union(count))
        }
    }

    @Test func theCountScalesWithTheEye() throws {
        let big = EyePlacement(position: CGPoint(x: 0.25, y: 0.5), scale: 2)
        let layout = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: big)
        #expect(eye(layout) == CGRect(x: 839, y: 699, width: 42, height: 42))
        let count = layout.onScreen(try #require(layout.countFrame))
        #expect(count == CGRect(x: 889, y: 704, width: 36, height: 32))
        #expect(EyeLayout.collapsedOutline(layout).bottomRadius == 21)
    }

    @Test func theEyeStaysInsideItsScreen() {
        let bottomLeft = EyePlacement(position: CGPoint(x: 0, y: 0))
        let topRight = EyePlacement(position: CGPoint(x: 1, y: 1), scale: 3)
        #expect(eye(EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: bottomLeft)).origin == .zero)
        #expect(eye(EyeLayout.collapsed(on: external, waitingCount: 0, placement: bottomLeft)).origin
            == CGPoint(x: -1920, y: 200))
        let corner = eye(EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: topRight))
        #expect(corner == CGRect(x: 3377, y: 1377, width: 63, height: 63))
        // Dragged past the edge, the eye stops at it.
        let beyond = EyePlacement(position: CGPoint(x: -0.3, y: 1.6))
        let clamped = eye(EyeLayout.collapsed(on: external, waitingCount: 0, placement: beyond))
        #expect(clamped.minX == -1920)
        #expect(clamped.maxY == 1280)
    }

    @Test func theCountMovesToTheLeftAtTheScreensRightEdge() throws {
        let edge = EyePlacement(position: CGPoint(x: 1, y: 0.5))
        let layout = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: edge)
        let count = layout.onScreen(try #require(layout.countFrame))
        #expect(count.maxX == eye(layout).minX - 4)
        #expect(ultrawide.frame.contains(layout.panelFrame))
    }

    @Test func theEyeKeepsOutOfTheNotch() {
        // Dropped on the notch's middle: the shortest way out is down, below the notch.
        let onNotch = EyePlacement(position: CGPoint(x: 0.5, y: 1))
        let below = eye(EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: onNotch))
        #expect(below == CGRect(x: 744, y: 926, width: 24, height: 24))
        // Near the notch's left edge: out to the left, still at the top.
        let nearEdge = EyePlacement(position: CGPoint(x: 0.4375, y: 1))
        let left = eye(EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: nearEdge))
        #expect(left == CGRect(x: 638, y: 958, width: 24, height: 24))
    }

    @Test func theCountKeepsOutOfTheNotchToo() throws {
        let nearEdge = EyePlacement(position: CGPoint(x: 0.4375, y: 1))
        let layout = EyeLayout.collapsed(on: mbp14, waitingCount: 2, placement: nearEdge)
        let count = layout.onScreen(try #require(layout.countFrame))
        #expect(count.maxX == eye(layout).minX - 4)
    }

    @Test func aResizedEyeStaysAtItsUsualSpot() {
        let bigger = EyePlacement(scale: 2)
        // Centred on the menu bar as before, grown down from the top of the screen.
        let wide = eye(EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: bigger))
        #expect(wide == CGRect(x: 1699, y: 1398, width: 42, height: 42))
        // Where the left wing's eye was, kept left of the notch.
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: bigger)
        #expect(eye(notch) == CGRect(x: 614, y: 934, width: 48, height: 48))
        #expect(notch.shapeFrame == nil)
    }

    @Test func aPositionRoundTripsThroughTheEyesCentre() {
        let placement = EyePlacement(position: CGPoint(x: 0.3, y: 0.4), scale: 1.7)
        for screen in screens {
            let center = EyeLayout.eyeCenter(of: EyeLayout.collapsed(on: screen, waitingCount: 2, placement: placement))
            let position = EyeLayout.position(of: center, on: screen)
            #expect(close(position.x, 0.3))
            #expect(close(position.y, 0.4))
        }
    }

    @Test func aMovedEyeKeepsItsShape() {
        let elsewhere = EyePlacement(position: CGPoint(x: 0.3, y: 0.7))
        let one = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: quarter)
        #expect(one.isSameShape(as: EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: elsewhere)))
        #expect(one.isSameShape(as: EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: quarter)) == false)
        let bigger = EyePlacement(position: CGPoint(x: 0.25, y: 0.5), scale: 2)
        #expect(one.isSameShape(as: EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: bigger)) == false)
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 0)
        #expect(notch.isSameShape(as: EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: quarter)) == false)
    }

    @Test func theEyeCanBeGrabbedByItsShapeAndItsCount() {
        let layout = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: quarter)
        let outlines = EyeLayout.grabOutlines(layout)
        func grabs(_ point: CGPoint) -> Bool { outlines.contains { $0.contains(point) } }
        #expect(grabs(CGPoint(x: 860, y: 720)))
        #expect(grabs(CGPoint(x: 883.5, y: 720)))
        // The gap between them, and the corner of the eye's square, are not the eye.
        #expect(grabs(CGPoint(x: 872.5, y: 720)) == false)
        #expect(grabs(CGPoint(x: 850, y: 710)) == false)
        // The notch's eye is its whole shape.
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 1)
        #expect(EyeLayout.grabOutlines(notch).contains { $0.contains(CGPoint(x: 870, y: 970)) })
    }

    // MARK: The panel

    @Test func atTheDefaultSpotThePanelBelowIsExactlyAsBefore() {
        for screen in screens {
            let collapsed = EyeLayout.collapsed(on: screen, waitingCount: 1)
            for height in [100, 300, 5000] as [CGFloat] {
                #expect(
                    EyeLayout.expandedFrame(
                        on: screen, contentHeight: height, collapsed: collapsed, placement: .standard, side: .below)
                        == EyeLayout.expandedFrame(on: screen, contentHeight: height))
            }
            #expect(EyeLayout.stageFrame(on: screen, placement: .standard, side: .below) == EyeLayout.stageFrame(on: screen))
            #expect(EyeLayout.motionMargin(on: screen, placement: .standard, side: .below) == EyeLayout.motionMargin(on: screen))
            let today = EyeLayout.expandedFrame(on: screen, contentHeight: 300)
            #expect(EyeLayout.expandedOutline(today, on: screen) == EyeLayout.expandedOutline(today))
        }
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 0)
        #expect(EyeLayout.topInset(on: mbp14, collapsed: notch, placement: .standard, side: .below) == 32)
        let plain = EyeLayout.collapsed(on: ultrawide, waitingCount: 0)
        #expect(EyeLayout.topInset(on: ultrawide, collapsed: plain, placement: .standard, side: .below) == 0)
    }

    @Test func thePanelAtTheTopIsSquareOnTopOnEveryDisplay() {
        for screen in screens + [lowered] {
            for height in [150, 300, 5000] as [CGFloat] {
                let frame = EyeLayout.expandedFrame(on: screen, contentHeight: height)
                #expect(EyeLayout.expandedOutline(frame, on: screen) == EyeLayout.expandedOutline(frame))
            }
        }
    }

    @Test func atTheDefaultSpotAPanelAboveOpensBelowAsBefore() {
        for screen in screens {
            let collapsed = EyeLayout.collapsed(on: screen, waitingCount: 0)
            let side = EyeLayout.openingSide(
                .above, on: screen, collapsed: collapsed, placement: .standard, contentHeight: 300)
            #expect(side == .below)
        }
    }

    @Test func aFloatingEyesPanelOpensBesideItOnTheChosenSide() {
        // The eye spans x 1709.5…1730.5, y 709.5…730.5; with two waiting its count reaches x 1752.5.
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: middle)
        #expect(eye(collapsed) == CGRect(x: 1709.5, y: 709.5, width: 21, height: 21))
        func frame(_ side: PanelSide, count: Int = 0) -> CGRect {
            let layout = EyeLayout.collapsed(on: ultrawide, waitingCount: count, placement: middle)
            return EyeLayout.expandedFrame(on: ultrawide, contentHeight: 300, collapsed: layout, placement: middle, side: side)
        }
        // 8 pt from the eye and its count, centred on the eye.
        #expect(frame(.below) == CGRect(x: 1400, y: 401.5, width: 640, height: 300))
        #expect(frame(.above) == CGRect(x: 1400, y: 738.5, width: 640, height: 300))
        #expect(frame(.left) == CGRect(x: 1061.5, y: 570, width: 640, height: 300))
        #expect(frame(.right) == CGRect(x: 1760.5, y: 570, width: 640, height: 300))
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: middle)
        let counted = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: middle)
        for side in PanelSide.allCases {
            #expect(EyeLayout.openingSide(side, on: ultrawide, collapsed: collapsed, placement: middle, contentHeight: 300) == side)
            #expect(EyeLayout.topInset(on: mbp14, collapsed: notch, placement: middle, side: side) == 0)
            #expect(EyeLayout.hangsFromTop(on: ultrawide, collapsed: collapsed, placement: middle, side: side) == false)
            // The eye and its count stay visible beside the open panel, which doesn't move when the count comes.
            #expect(EyeLayout.panel(frame(side), covers: collapsed) == false)
            #expect(frame(side).intersects(counted.panelFrame) == false)
            #expect(frame(side, count: 2) == frame(side))
        }
    }

    @Test func theWindowShowsAnUncoveredEyeInEveryPhase() {
        let placements = [middle, quarter, EyePlacement(position: CGPoint(x: 0.7, y: 0.3), scale: 2.5), EyePlacement(scale: 0.8)]
        var hidden: [String] = []
        for screen in screens {
            for placement in placements {
                for count in [0, 2] {
                    let collapsed = EyeLayout.collapsed(on: screen, waitingCount: count, placement: placement)
                    let eyeOutline = EyeLayout.collapsedOutline(collapsed).frame
                    for wanted in PanelSide.allCases {
                        let side = EyeLayout.openingSide(
                            wanted, on: screen, collapsed: collapsed, placement: placement, contentHeight: 300)
                        let expanded = EyeLayout.expandedFrame(
                            on: screen, contentHeight: 300, collapsed: collapsed, placement: placement, side: side)
                        guard !EyeLayout.panel(expanded, covers: collapsed) else { continue }
                        let stage = EyeLayout.stageFrame(on: screen, placement: placement, side: wanted)
                        let margin = EyeLayout.motionMargin(on: screen, placement: placement, side: wanted)
                        // The window through a whole open-and-close cycle, as the window controller drives it.
                        let start = ContinuousClock.now
                        var window = EyeWindowFrame(footprint: PanelPhase.collapsed.footprint(collapsed: collapsed, expanded: expanded))
                        var frames = [("collapsed", window.frame(within: stage))]
                        window.animate(
                            to: PanelPhase.opening.footprint(collapsed: collapsed, expanded: expanded),
                            at: start, for: .milliseconds(700), margin: margin)
                        frames.append(("opening", window.frame(within: stage)))
                        window.settle(at: start + .milliseconds(700))
                        frames.append(("expanded", window.frame(within: stage)))
                        window.animate(
                            to: PanelPhase.closing.footprint(collapsed: collapsed, expanded: expanded),
                            at: start + .seconds(1), for: .milliseconds(640), margin: margin)
                        frames.append(("closing", window.frame(within: stage)))
                        window.settle(at: start + .seconds(2))
                        frames.append(("collapsed again", window.frame(within: stage)))
                        for (phase, frame) in frames where !frame.contains(eyeOutline) || !stage.contains(eyeOutline) {
                            hidden.append("\(placement) \(wanted) \(count) \(phase)")
                        }
                    }
                }
            }
        }
        #expect(hidden.isEmpty)
    }

    @Test func aMovedEyesPanelIsAsTallAsBeforeAtMost() {
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: middle)
        let frame = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 5000, collapsed: collapsed, placement: middle, side: .left)
        #expect(frame.size == EyeLayout.expandedFrame(on: ultrawide, contentHeight: 5000).size)
    }

    @Test func withoutRoomThePanelOpensOnTheOppositeSide() {
        func side(_ wanted: PanelSide, at position: CGPoint) -> PanelSide {
            let placement = EyePlacement(position: position)
            let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: placement)
            return EyeLayout.openingSide(wanted, on: ultrawide, collapsed: collapsed, placement: placement, contentHeight: 300)
        }
        #expect(side(.below, at: CGPoint(x: 0.5, y: 0.1)) == .above)
        #expect(side(.above, at: CGPoint(x: 0.5, y: 0.9)) == .below)
        #expect(side(.left, at: CGPoint(x: 0.05, y: 0.5)) == .right)
        #expect(side(.right, at: CGPoint(x: 0.95, y: 0.5)) == .left)
    }

    @Test func withRoomOnNeitherSideThePanelStaysOnTheChosenSideAndOnScreen() {
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: middle)
        for wanted in [PanelSide.below, .above] {
            let side = EyeLayout.openingSide(wanted, on: ultrawide, collapsed: collapsed, placement: middle, contentHeight: 800)
            #expect(side == wanted)
        }
        func frame(_ side: PanelSide) -> CGRect {
            EyeLayout.expandedFrame(on: ultrawide, contentHeight: 800, collapsed: collapsed, placement: middle, side: side)
        }
        #expect(frame(.below) == CGRect(x: 1400, y: 0, width: 640, height: 800))
        #expect(frame(.above) == CGRect(x: 1400, y: 615, width: 640, height: 800))
    }

    @Test func thePanelIsAlwaysFullyInTheVisibleFrame() {
        let fractions: [CGFloat] = [0, 0.02, 0.3, 0.5, 0.7, 0.98, 1]
        var placements = [EyePlacement(scale: 0.5), EyePlacement(scale: 3)]
        for x in fractions {
            for y in fractions {
                for scale in [0.5, 1, 3] as [CGFloat] {
                    placements.append(EyePlacement(position: CGPoint(x: x, y: y), scale: scale))
                }
            }
        }
        var outside: [String] = []
        for screen in screens {
            for placement in placements {
                let collapsed = EyeLayout.collapsed(on: screen, waitingCount: 2, placement: placement)
                for wanted in PanelSide.allCases {
                    for height in [150, 400, 5000] as [CGFloat] {
                        let side = EyeLayout.openingSide(
                            wanted, on: screen, collapsed: collapsed, placement: placement, contentHeight: height)
                        let frame = EyeLayout.expandedFrame(
                            on: screen, contentHeight: height, collapsed: collapsed, placement: placement, side: side)
                        // A panel hanging from the top covers the menu bar, as it always did.
                        let hangs = EyeLayout.hangsFromTop(on: screen, collapsed: collapsed, placement: placement, side: side)
                        let visible = screen.visibleFrame
                        let inside = hangs
                            ? frame.maxY == screen.frame.maxY && frame.minY >= visible.minY
                                && frame.minX >= visible.minX && frame.maxX <= visible.maxX
                            : visible.contains(frame)
                        if !inside { outside.append("\(placement) \(wanted) \(height)") }
                    }
                }
            }
        }
        #expect(outside.isEmpty)
    }

    @Test func belowAnEyeInTheMenuBarThePanelHangsFromTheTopAsBefore() {
        // Resized at the default spot: centred on the eye, which is at the top centre.
        let smaller = EyePlacement(scale: 0.8)
        let plain = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: smaller)
        let frame = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: plain, placement: smaller, side: .below)
        #expect(frame == EyeLayout.expandedFrame(on: ultrawide, contentHeight: 300))
        #expect(EyeLayout.hangsFromTop(on: ultrawide, collapsed: plain, placement: smaller, side: .below))
        #expect(EyeLayout.panel(frame, covers: plain))
        #expect(EyeLayout.expandedOutline(frame, on: ultrawide).topRadius == 0)
        #expect(EyeLayout.topInset(on: ultrawide, collapsed: plain, placement: smaller, side: .below) == 0)

        // Larger on the notch display: centred on the eye left of the notch, content below the notch.
        let bigger = EyePlacement(scale: 2)
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: bigger)
        let hanging = EyeLayout.expandedFrame(
            on: mbp14, contentHeight: 300, collapsed: notch, placement: bigger, side: .below)
        #expect(hanging == CGRect(x: 318, y: 682, width: 640, height: 300))
        #expect(EyeLayout.topInset(on: mbp14, collapsed: notch, placement: bigger, side: .below) == 32)
        #expect(EyeLayout.panel(hanging, covers: notch))

        // Dragged into the menu bar's corner: it hangs at the screen's edge.
        let corner = EyePlacement(position: CGPoint(x: 0, y: 1))
        let cornerEye = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: corner)
        let atCorner = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: cornerEye, placement: corner, side: .below)
        #expect(atCorner == CGRect(x: 0, y: 1140, width: 640, height: 300))
        #expect(EyeLayout.panel(atCorner, covers: cornerEye))
        // There is no room above it, so above hangs below too.
        #expect(EyeLayout.openingSide(.above, on: ultrawide, collapsed: cornerEye, placement: corner, contentHeight: 300) == .below)
    }

    @Test func aLargeEyeReachingIntoTheMenuBarCountsAsInIt() {
        // 63 pt tall, with its top at the top of the screen.
        let large = EyePlacement(position: CGPoint(x: 0.25, y: 1), scale: 3)
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: large)
        #expect(EyeLayout.hangsFromTop(on: ultrawide, collapsed: collapsed, placement: large, side: .below))
        let frame = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: collapsed, placement: large, side: .below)
        #expect(frame.maxY == 1440)
        #expect(EyeLayout.panel(frame, covers: collapsed))
    }

    @Test func justBelowTheNotchThePanelOpensUnderTheEye() {
        // Dropped on the notch, the eye sits right under it, out of the menu bar.
        let onNotch = EyePlacement(position: CGPoint(x: 0.5, y: 1))
        let collapsed = EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: onNotch)
        #expect(EyeLayout.hangsFromTop(on: mbp14, collapsed: collapsed, placement: onNotch, side: .below) == false)
        let frame = EyeLayout.expandedFrame(
            on: mbp14, contentHeight: 300, collapsed: collapsed, placement: onNotch, side: .below)
        #expect(frame == CGRect(x: 436, y: 618, width: 640, height: 300))
        #expect(EyeLayout.panel(frame, covers: collapsed) == false)
        #expect(EyeLayout.expandedOutline(frame, on: mbp14).topRadius == EyeLayout.panelCornerRadius)
    }

    @Test func besideAnEyeInTheMenuBarThePanelOpensUnderTheMenuBar() {
        let smaller = EyePlacement(scale: 0.8)
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: smaller)
        for side in [PanelSide.left, .right] {
            #expect(EyeLayout.hangsFromTop(on: ultrawide, collapsed: collapsed, placement: smaller, side: side) == false)
            let frame = EyeLayout.expandedFrame(
                on: ultrawide, contentHeight: 300, collapsed: collapsed, placement: smaller, side: side)
            #expect(frame.maxY == 1415)
            #expect(EyeLayout.panel(frame, covers: collapsed) == false)
        }
    }

    @Test func thePanelIsKeptClearOfTheNotchWhenTheMenuBarHides() {
        // With the menu bar hidden the visible frame reaches the top, but the notch still covers it.
        var hidden = mbp14
        hidden.visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let placement = EyePlacement(position: CGPoint(x: 0.5, y: 0.9))
        let collapsed = EyeLayout.collapsed(on: hidden, waitingCount: 0, placement: placement)
        let frame = EyeLayout.expandedFrame(
            on: hidden, contentHeight: 300, collapsed: collapsed, placement: placement, side: .above)
        #expect(frame.maxY == 950)
    }

    // MARK: Grabbing and resizing

    @Test func grabbingTheNotchPutsTheEyeUnderThePointer() {
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 1)
        let onCount = CGPoint(x: 867, y: 966)
        #expect(EyeLayout.grabCenter(of: notch, pressedAt: onCount) == onCount)
        let nearTheEye = CGPoint(x: 648, y: 968)
        #expect(EyeLayout.grabCenter(of: notch, pressedAt: nearTheEye) == nearTheEye)
        // Dragged from there, the circle's centre is the pointer.
        var drag = EyeDrag(start: onCount, eyeCenter: EyeLayout.grabCenter(of: notch, pressedAt: onCount))
        #expect(drag.move(to: CGPoint(x: 880, y: 800)) == CGPoint(x: 880, y: 800))
    }

    @Test func grabbingACircleKeepsWhereItWasHeldButNotFromItsCount() {
        let free = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: quarter)
        #expect(EyeLayout.grabCenter(of: free, pressedAt: CGPoint(x: 865, y: 716)) == CGPoint(x: 860, y: 720))
        let onCount = CGPoint(x: 883.5, y: 720)
        #expect(EyeLayout.grabCenter(of: free, pressedAt: onCount) == onCount)
        // The menu-bar eye and its count alike.
        let plain = EyeLayout.collapsed(on: ultrawide, waitingCount: 2)
        let center = EyeLayout.eyeCenter(of: plain)
        #expect(EyeLayout.grabCenter(of: plain, pressedAt: CGPoint(x: center.x + 2, y: center.y + 1)) == center)
        let plainCount = plain.onScreen(plain.countFrame ?? .zero)
        let onPlainCount = CGPoint(x: plainCount.midX, y: plainCount.midY)
        #expect(EyeLayout.grabCenter(of: plain, pressedAt: onPlainCount) == onPlainCount)
    }

    @Test func resizingTheNotchPutsTheCircleUnderThePointer() {
        let notch = EyeLayout.collapsed(on: mbp14, waitingCount: 1)
        let pointer = CGPoint(x: 867, y: 966)
        let anchored = EyeLayout.anchoredForResize(.standard, layout: notch, pointer: pointer, on: mbp14)
        #expect(anchored.scale == 1)
        let resized = anchored.resized(byScroll: 10, precise: true, inverted: false)
        let layout = EyeLayout.collapsed(on: mbp14, waitingCount: 1, placement: resized)
        #expect(EyeLayout.collapsedOutline(layout).contains(pointer))
        let center = EyeLayout.eyeCenter(of: layout)
        #expect(close(center.x, pointer.x))
        #expect(close(center.y, pointer.y))
    }

    @Test func resizingTheMenuBarEyeKeepsItsSpotUnlessThePointerIsOffIt() throws {
        let plain = EyeLayout.collapsed(on: ultrawide, waitingCount: 2)
        let onEye = EyeLayout.eyeCenter(of: plain)
        #expect(EyeLayout.anchoredForResize(.standard, layout: plain, pointer: onEye, on: ultrawide) == .standard)
        let count = plain.onScreen(try #require(plain.countFrame))
        let onCount = CGPoint(x: count.midX, y: count.midY)
        let anchored = EyeLayout.anchoredForResize(.standard, layout: plain, pointer: onCount, on: ultrawide)
        let layout = EyeLayout.collapsed(
            on: ultrawide, waitingCount: 2, placement: anchored.resized(byScroll: 10, precise: true, inverted: false))
        #expect(EyeLayout.collapsedOutline(layout).contains(onCount))
    }

    @Test func resizingAMovedOrResizedEyeKeepsItsPlace() {
        let moved = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: quarter)
        #expect(EyeLayout.anchoredForResize(quarter, layout: moved, pointer: CGPoint(x: 200, y: 200), on: ultrawide) == quarter)
        let bigger = EyePlacement(scale: 2)
        let resized = EyeLayout.collapsed(on: mbp14, waitingCount: 1, placement: bigger)
        #expect(EyeLayout.anchoredForResize(bigger, layout: resized, pointer: CGPoint(x: 867, y: 966), on: mbp14) == bigger)
    }

    @Test func aFreePanelIsRoundedAllRound() {
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: middle)
        let frame = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: collapsed, placement: middle, side: .right)
        let outline = EyeLayout.expandedOutline(frame, on: ultrawide)
        #expect(outline.frame == frame)
        #expect(outline.topRadius == EyeLayout.panelCornerRadius)
        #expect(outline.bottomRadius == EyeLayout.panelCornerRadius)
    }

    @Test func theDefaultPanelCoversTheEye() {
        for screen in screens {
            let collapsed = EyeLayout.collapsed(on: screen, waitingCount: 2)
            #expect(EyeLayout.panel(EyeLayout.expandedFrame(on: screen, contentHeight: 300), covers: collapsed))
        }
    }

    // MARK: The stage

    @Test func theStageHoldsTheEyeAndThePanelOnEitherSideWithRoomToOvershoot() {
        let placements = [
            EyePlacement.standard, middle, EyePlacement(scale: 3),
            EyePlacement(position: CGPoint(x: 0.02, y: 0.98), scale: 0.5),
            EyePlacement(position: CGPoint(x: 0.98, y: 0.02), scale: 3),
            EyePlacement(position: CGPoint(x: 0.5, y: 1), scale: 2)
        ]
        var missing: [String] = []
        for screen in screens {
            for placement in placements {
                for side in PanelSide.allCases {
                    let stage = EyeLayout.stageFrame(on: screen, placement: placement, side: side)
                    let margin = EyeLayout.motionMargin(on: screen, placement: placement, side: side)
                    if !screen.frame.contains(stage) { missing.append("\(placement) \(side) leaves the screen") }
                    var shapes: [CGRect] = []
                    for count in 0...2 {
                        shapes.append(EyeLayout.collapsed(on: screen, waitingCount: count, placement: placement).panelFrame)
                    }
                    let collapsed = EyeLayout.collapsed(on: screen, waitingCount: 2, placement: placement)
                    let heights: [CGFloat] = [150, 400, 5000]
                    // Whichever side the panel opens on, it may then take any height.
                    let opening = Set(heights.map {
                        EyeLayout.openingSide(side, on: screen, collapsed: collapsed, placement: placement, contentHeight: $0)
                    })
                    for candidate in opening {
                        for height in heights {
                            shapes.append(EyeLayout.expandedFrame(
                                on: screen, contentHeight: height, collapsed: collapsed, placement: placement, side: candidate))
                        }
                    }
                    for shape in shapes {
                        let room = shape.insetBy(dx: -margin, dy: -margin).intersection(screen.frame)
                        if !stage.contains(room) { missing.append("\(placement) \(side) \(shape)") }
                    }
                }
            }
        }
        #expect(missing.isEmpty)
    }

    @Test func aFreePanelsMarginCoversItsLongestTravel() throws {
        let overshoot = try #require(PanelMotion().shapeOpen).curve.overshoot
        for screen in screens {
            // Beside the eye, the panel's far edge travels across the eye, its count, the gap and the panel.
            let room = EyeLayout.collapsed(on: screen, waitingCount: 2, placement: middle).panelFrame
            let travel = EyeLayout.panelWidth + EyeLayout.panelGap + room.width
            for side in PanelSide.allCases {
                #expect(EyeLayout.motionMargin(on: screen, placement: middle, side: side) >= 2 * overshoot * travel)
            }
        }
    }
}

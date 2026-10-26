import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct ClickThroughTests {
    let ultrawide = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
        visibleFrame: CGRect(x: 0, y: 0, width: 3440, height: 1415),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
    let mbp14 = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662)

    let circle = EyeOutline(frame: CGRect(x: 0, y: 0, width: 63, height: 63), topRadius: 31.5, bottomRadius: 31.5)
    let capsule = EyeOutline(frame: CGRect(x: 71, y: 23.5, width: 36, height: 16), topRadius: 8, bottomRadius: 8)

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    private func window(collapsed: CollapsedLayout, expanded: CGRect?) -> CGRect {
        guard let expanded else { return collapsed.panelFrame }
        return PanelPhase.expanded.footprint(collapsed: collapsed, expanded: expanded)
    }

    private func hasGap(_ collapsed: CollapsedLayout, expanded: CGRect? = nil) -> Bool {
        ClickThrough.hasGap(
            in: window(collapsed: collapsed, expanded: expanded),
            around: EyeLayout.clickOutlines(collapsed, expanded: expanded))
    }

    // MARK: Distance and hits

    @Test func theDistanceToAnOutlineIsZeroInsideAndMeasuredOutside() {
        #expect(circle.distance(to: CGPoint(x: 31.5, y: 31.5)) == 0)
        #expect(close(circle.distance(to: CGPoint(x: 31.5, y: 73.5)), 10.5))
        #expect(close(circle.distance(to: CGPoint(x: 70, y: 31.5)), 7))
        // The corner of the circle's square.
        let cornerDepth: CGFloat = 31.5 * (2.squareRoot() - 1)
        #expect(close(circle.distance(to: .zero), cornerDepth))
    }

    @Test func aSquareTopHasNoRoundedCorners() {
        let notch = EyeOutline(frame: CGRect(x: 0, y: 0, width: 200, height: 32), topRadius: 0, bottomRadius: 10)
        #expect(notch.distance(to: CGPoint(x: 0, y: 32)) == 0)
        #expect(close(notch.distance(to: CGPoint(x: -2, y: 34)), 8.squareRoot()))
        #expect(close(notch.distance(to: .zero), 10 * (2.squareRoot() - 1)))
    }

    @Test func aPointHitsWhenItIsInsideOneOfTheOutlines() {
        #expect(ClickThrough.hits(CGPoint(x: 31.5, y: 31.5), [circle, capsule]))
        #expect(ClickThrough.hits(CGPoint(x: 89, y: 31.5), [circle, capsule]))
        #expect(ClickThrough.hits(CGPoint(x: 2, y: 2), [circle, capsule]) == false)
        #expect(ClickThrough.hits(CGPoint(x: 67, y: 31.5), [circle, capsule]) == false)
        #expect(ClickThrough.hits(.zero, []) == false)
    }

    // MARK: Gaps

    @Test func aWindowThatIsAllShapeHasNoGap() {
        let panel = EyeOutline(frame: CGRect(x: 10, y: 10, width: 640, height: 300), topRadius: 0, bottomRadius: 0)
        #expect(ClickThrough.hasGap(in: panel.frame, around: [panel]) == false)
        #expect(ClickThrough.hasGap(in: circle.frame.union(capsule.frame), around: [circle, capsule]))
    }

    @Test func theUsualEyesCornersAreNoGap() {
        for screen in [ultrawide, mbp14] {
            for count in 0...1 {
                #expect(hasGap(EyeLayout.collapsed(on: screen, waitingCount: count)) == false)
            }
        }
        #expect(hasGap(EyeLayout.collapsed(on: mbp14, waitingCount: 3)) == false)
        // Nor are those of a moved eye at its usual size.
        let moved = EyePlacement(position: CGPoint(x: 0.3, y: 0.5))
        #expect(hasGap(EyeLayout.collapsed(on: mbp14, waitingCount: 0, placement: moved)) == false)
    }

    @Test func aLargeEyesCornersAndTheRoomAroundItsCountAreGaps() {
        let large = EyePlacement(position: CGPoint(x: 0.5, y: 0.5), scale: 3)
        #expect(hasGap(EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: large)))
        let counted = EyePlacement(position: CGPoint(x: 0.5, y: 0.5), scale: 2)
        #expect(hasGap(EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: counted)))
        // Also the menu-bar eye with its count beside it.
        #expect(hasGap(EyeLayout.collapsed(on: ultrawide, waitingCount: 2)))
    }

    @Test func theOpenPanelAtTheDefaultSpotIsAllShape() {
        for screen in [ultrawide, mbp14] {
            for count in 0...2 {
                let collapsed = EyeLayout.collapsed(on: screen, waitingCount: count)
                let expanded = EyeLayout.expandedFrame(on: screen, contentHeight: 300)
                #expect(hasGap(collapsed, expanded: expanded) == false)
            }
        }
    }

    @Test func anOpenPanelBesideItsEyeLetsClicksThroughBetweenThem() throws {
        // An eye in the menu bar, its panel to the left under the menu bar.
        let placement = EyePlacement(scale: 0.8)
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: placement)
        let expanded = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: collapsed, placement: placement, side: .left)
        #expect(EyeLayout.panel(expanded, covers: collapsed) == false)
        #expect(hasGap(collapsed, expanded: expanded))

        let outlines = EyeLayout.clickOutlines(collapsed, expanded: expanded)
        #expect(ClickThrough.hits(CGPoint(x: expanded.midX, y: expanded.midY), outlines))
        #expect(ClickThrough.hits(EyeLayout.eyeCenter(of: collapsed), outlines))
        let count = collapsed.onScreen(try #require(collapsed.countFrame))
        #expect(ClickThrough.hits(CGPoint(x: count.midX, y: count.midY), outlines))
        // In the menu bar above the panel, left of the eye: the click goes through.
        #expect(ClickThrough.hits(CGPoint(x: expanded.minX + 10, y: expanded.maxY + 10), outlines) == false)
    }

    @Test func thePanelsRoundedCornersStayThePanels() {
        let placement = EyePlacement(scale: 0.8)
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 0, placement: placement)
        let expanded = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: collapsed, placement: placement, side: .left)
        let outlines = EyeLayout.clickOutlines(collapsed, expanded: expanded)
        #expect(ClickThrough.hits(CGPoint(x: expanded.minX + 1, y: expanded.minY + 1), outlines))
    }

    @Test func aCountUnderThePanelTakesNoClicks() {
        // Below an eye in the menu bar the panel hangs from the top over it.
        let smaller = EyePlacement(scale: 0.8)
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: smaller)
        let expanded = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: collapsed, placement: smaller, side: .below)
        #expect(EyeLayout.clickOutlines(collapsed, expanded: expanded).count == 2)
        #expect(EyeLayout.clickOutlines(collapsed, expanded: nil).count == 2)
    }

    @Test func aFloatingEyeAndItsCountTakeClicksBesideTheOpenPanel() {
        let middle = EyePlacement(position: CGPoint(x: 0.5, y: 0.5))
        let collapsed = EyeLayout.collapsed(on: ultrawide, waitingCount: 2, placement: middle)
        let expanded = EyeLayout.expandedFrame(
            on: ultrawide, contentHeight: 300, collapsed: collapsed, placement: middle, side: .right)
        let outlines = EyeLayout.clickOutlines(collapsed, expanded: expanded)
        #expect(outlines.count == 3)
        #expect(ClickThrough.hits(EyeLayout.eyeCenter(of: collapsed), outlines))
        // The room above and below the eye, left of the panel, lets clicks through.
        let window = PanelPhase.expanded.footprint(collapsed: collapsed, expanded: expanded)
        #expect(ClickThrough.hasGap(in: window, around: outlines))
    }
}

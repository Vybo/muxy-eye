import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct EyePlacementTests {
    let moved = EyePlacement(position: CGPoint(x: 0.25, y: 0.5))

    @Test func theDefaultSpotAndSizeAreNotCustomized() {
        #expect(EyePlacement.standard.isCustomized == false)
        #expect(EyePlacement().isCustomized == false)
        #expect(EyePlacement.standard.position == nil)
        #expect(EyePlacement.standard.scale == 1)
    }

    @Test func movingOrResizingCustomizesIt() {
        #expect(moved.isCustomized)
        #expect(EyePlacement(scale: 1.5).isCustomized)
        #expect(EyePlacement(position: CGPoint(x: 0.5, y: 1), scale: 0.7).isCustomized)
    }

    @Test func sanitizingKeepsThePositionOnTheScreenAndTheSizeInRange() {
        let wild = EyePlacement(position: CGPoint(x: -0.2, y: 1.4), scale: 9)
        #expect(wild.sanitized == EyePlacement(position: CGPoint(x: 0, y: 1), scale: 3))
        #expect(EyePlacement(scale: 0.1).sanitized.scale == 0.5)
        #expect(moved.sanitized == moved)
    }

    @Test func sanitizingDropsValuesThatAreNotNumbers() {
        let broken = EyePlacement(position: CGPoint(x: CGFloat.nan, y: 0.5), scale: .infinity)
        #expect(broken.sanitized == .standard)
    }

    @Test func scrollingUpGrowsTheEyeAndDownShrinksIt() {
        #expect(moved.resized(byScroll: 10, precise: true, inverted: false).scale > 1)
        #expect(moved.resized(byScroll: -10, precise: true, inverted: false).scale < 1)
        #expect(moved.resized(byScroll: 0, precise: true, inverted: false) == moved)
    }

    @Test func naturalScrollingGrowsItWithTheSameMovement() {
        let natural = moved.resized(byScroll: -10, precise: true, inverted: true)
        let classic = moved.resized(byScroll: 10, precise: true, inverted: false)
        #expect(natural.scale == classic.scale)
    }

    @Test func aWheelStepResizesByAboutATenth() {
        let step = moved.resized(byScroll: 1, precise: false, inverted: false)
        #expect(abs(step.scale - 1.105) < 0.001)
        #expect(step.scale == moved.resized(byScroll: EyePlacement.pointsPerLine, precise: true, inverted: false).scale)
    }

    @Test func trackpadPointsResizeInSmallSteps() {
        let point = moved.resized(byScroll: 1, precise: true, inverted: false)
        #expect(point.scale > 1)
        #expect(point.scale < 1.01)
    }

    @Test func resizingBackAndForthReturnsToTheSameSize() {
        let back = moved
            .resized(byScroll: 37, precise: true, inverted: false)
            .resized(byScroll: -37, precise: true, inverted: false)
        #expect(abs(back.scale - 1) < 1e-9)
    }

    @Test func theSizeStaysBetweenHalfAndThreeTimesTheUsualOne() {
        #expect(moved.resized(byScroll: 10_000, precise: true, inverted: false).scale == 3)
        #expect(moved.resized(byScroll: -10_000, precise: true, inverted: false).scale == 0.5)
        #expect(EyePlacement.scales == 0.5...3)
    }

    @Test func resizingKeepsThePosition() {
        #expect(moved.resized(byScroll: 50, precise: true, inverted: false).position == moved.position)
        #expect(EyePlacement.standard.resized(byScroll: 50, precise: true, inverted: false).position == nil)
    }

    @Test func eachSideHasAnOpposite() {
        #expect(PanelSide.below.opposite == .above)
        #expect(PanelSide.above.opposite == .below)
        #expect(PanelSide.left.opposite == .right)
        #expect(PanelSide.right.opposite == .left)
        #expect(PanelSide.allCases == [.below, .above, .left, .right])
    }
}

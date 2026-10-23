import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct EyeLayoutTests {
    let ultrawide = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
        visibleFrame: CGRect(x: 0, y: 0, width: 3440, height: 1415),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
    let mbp14 = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662)

    @Test func ultrawideEyeCentered() {
        let layout = EyeLayout.collapsed(on: ultrawide, waitingCount: 0)
        #expect(layout.eyeFrame.width == 21)
        #expect(layout.eyeFrame.height == 21)
        #expect(layout.panelFrame.midX == 1720)
        #expect(layout.panelFrame.maxY == CGFloat(1440 - 2))
        #expect(layout.countFrame == nil)
        #expect(layout.shapeFrame == nil)
    }

    @Test func ultrawideBadgeAtTwo() throws {
        #expect(EyeLayout.collapsed(on: ultrawide, waitingCount: 1).countFrame == nil)
        let layout = EyeLayout.collapsed(on: ultrawide, waitingCount: 2)
        let count = try #require(layout.countFrame)
        #expect(count.width == 18)
        #expect(layout.panelFrame.width == CGFloat(21 + 4 + 18))
        #expect(count.minX == layout.eyeFrame.maxX + 4)
    }

    @Test func notchOneWingWhenNothingWaiting() {
        let layout = EyeLayout.collapsed(on: mbp14, waitingCount: 0)
        #expect(layout.panelFrame.minX == 628)
        #expect(layout.panelFrame.maxX == 850)
        #expect(layout.panelFrame.height == 32)
        #expect(layout.panelFrame.maxY == 982)
        #expect(layout.eyeFrame.width == 24)
        #expect(layout.countFrame == nil)
        #expect(layout.shapeFrame == CGRect(origin: .zero, size: layout.panelFrame.size))
    }

    @Test func notchTwoWingsWhenWaiting() throws {
        let layout = EyeLayout.collapsed(on: mbp14, waitingCount: 1)
        #expect(layout.panelFrame.minX == 628)
        #expect(layout.panelFrame.maxX == 884)
        let count = try #require(layout.countFrame)
        #expect(count.minX > layout.eyeFrame.maxX)
        #expect(count.midY == layout.panelFrame.height / 2)
    }

    @Test func expandedClampsHeight() {
        let frame = EyeLayout.expandedFrame(on: ultrawide, contentHeight: 2000)
        #expect(frame.width == 640)
        #expect(frame.midX == 1720)
        #expect(frame.maxY == 1440)
        #expect(frame.height == 849)
    }

    @Test func expandedCentredOnNotch() {
        let frame = EyeLayout.expandedFrame(on: mbp14, contentHeight: 100)
        #expect(frame.midX == 756)
        #expect(frame.height == 100)
    }

    @Test func stageCoversEveryShapeWithRoomToOvershootBelowTheScreenTop() {
        for screen in [ultrawide, mbp14] {
            let stage = EyeLayout.stageFrame(on: screen)
            let margin = EyeLayout.motionMargin(on: screen)
            let tallest = EyeLayout.expandedFrame(on: screen, contentHeight: .greatestFiniteMagnitude)
            #expect(stage.maxY == screen.frame.maxY)
            #expect(stage.minX <= tallest.minX - margin)
            #expect(stage.maxX >= tallest.maxX + margin)
            #expect(stage.minY <= tallest.minY - margin)
            for count in 0...2 {
                #expect(stage.contains(EyeLayout.collapsed(on: screen, waitingCount: count).panelFrame))
            }
        }
    }

    @Test func marginCoversTheTallestPanelsOvershoot() throws {
        let overshoot = try #require(PanelMotion().shapeOpen).curve.overshoot
        for screen in [ultrawide, mbp14] {
            let tallest = EyeLayout.expandedFrame(on: screen, contentHeight: .greatestFiniteMagnitude)
            #expect(EyeLayout.motionMargin(on: screen) >= overshoot * tallest.height)
        }
    }

    @Test func stageRectsAreMeasuredFromTheStagesTopLeft() {
        let stage = CGRect(x: 100, y: 500, width: 600, height: 400)
        let rect = CGRect(x: 150, y: 880, width: 20, height: 10)
        #expect(EyeLayout.stageRect(rect, in: stage) == CGRect(x: 50, y: 10, width: 20, height: 10))
        #expect(EyeLayout.stageRect(stage, in: stage) == CGRect(origin: .zero, size: stage.size))
    }

    @Test func layoutFramesConvertToTheScreen() {
        let layout = EyeLayout.collapsed(on: mbp14, waitingCount: 1)
        let eye = layout.onScreen(layout.eyeFrame)
        #expect(eye.minX == layout.panelFrame.minX + layout.eyeFrame.minX)
        #expect(eye.minY == layout.panelFrame.minY + layout.eyeFrame.minY)
        #expect(eye.size == layout.eyeFrame.size)
    }

    @Test func plainOutlineIsTheEyesCircle() {
        let layout = EyeLayout.collapsed(on: ultrawide, waitingCount: 2)
        let outline = EyeLayout.collapsedOutline(layout)
        #expect(outline.frame == layout.onScreen(layout.eyeFrame))
        #expect(outline.topRadius == 10.5)
        #expect(outline.bottomRadius == 10.5)
    }

    @Test func notchOutlineIsTheWidenedNotch() {
        let layout = EyeLayout.collapsed(on: mbp14, waitingCount: 1)
        let outline = EyeLayout.collapsedOutline(layout)
        #expect(outline.frame == layout.panelFrame)
        #expect(outline.topRadius == 0)
        #expect(outline.bottomRadius == EyeLayout.notchCornerRadius)
    }

    @Test func expandedOutlineRoundsOnlyTheBottom() {
        let frame = EyeLayout.expandedFrame(on: mbp14, contentHeight: 300)
        let outline = EyeLayout.expandedOutline(frame)
        #expect(outline.frame == frame)
        #expect(outline.topRadius == 0)
        #expect(outline.bottomRadius == 22)
    }
}

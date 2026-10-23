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
}

import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct EyeDragTests {
    let start = CGPoint(x: 100, y: 100)
    let eye = CGPoint(x: 95, y: 104)

    @Test func aPressThatBarelyMovesIsAClick() {
        var drag = EyeDrag(start: start, eyeCenter: eye)
        #expect(drag.move(to: CGPoint(x: 102, y: 101)) == nil)
        #expect(drag.isDragging == false)
        #expect(drag.release(at: CGPoint(x: 103, y: 102)) == .click)
    }

    @Test func movingFourPointsMakesItADrag() {
        var drag = EyeDrag(start: start, eyeCenter: eye)
        #expect(drag.move(to: CGPoint(x: 103.9, y: 100)) == nil)
        #expect(drag.move(to: CGPoint(x: 104, y: 100)) == CGPoint(x: 99, y: 104))
        #expect(drag.isDragging)
        #expect(EyeDrag.threshold == 4)
    }

    @Test func theDistanceCountsInEveryDirection() {
        var diagonal = EyeDrag(start: start, eyeCenter: eye)
        #expect(diagonal.move(to: CGPoint(x: 97.2, y: 97.2)) == nil)
        #expect(diagonal.move(to: CGPoint(x: 97, y: 97)) != nil)
    }

    @Test func theEyeFollowsThePointerFromWhereItWasGrabbed() {
        var drag = EyeDrag(start: start, eyeCenter: eye)
        #expect(drag.move(to: CGPoint(x: 300, y: 40)) == CGPoint(x: 295, y: 44))
        #expect(drag.move(to: CGPoint(x: 310, y: 45)) == CGPoint(x: 305, y: 49))
        #expect(drag.release(at: CGPoint(x: 320, y: 50)) == .drop(CGPoint(x: 315, y: 54)))
    }

    @Test func aDragStaysADragWhenThePointerComesBack() {
        var drag = EyeDrag(start: start, eyeCenter: eye)
        _ = drag.move(to: CGPoint(x: 150, y: 100))
        #expect(drag.move(to: CGPoint(x: 101, y: 100)) == CGPoint(x: 96, y: 104))
        #expect(drag.release(at: start) == .drop(eye))
    }

    @Test func aQuickFlickWithoutMovesIsStillADrag() {
        let drag = EyeDrag(start: start, eyeCenter: eye)
        #expect(drag.release(at: CGPoint(x: 120, y: 100)) == .drop(CGPoint(x: 115, y: 104)))
    }
}

import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct EyeOutlineTests {
    /// A panel at the top of a screen, in screen coordinates (y up): square on top, 22 pt corners below.
    let panel = EyeOutline(frame: CGRect(x: 100, y: 500, width: 640, height: 300), topRadius: 0, bottomRadius: 22)
    let eye = EyeOutline(frame: CGRect(x: 10, y: 10, width: 20, height: 20), topRadius: 10, bottomRadius: 10)

    @Test func containsItsInside() {
        #expect(panel.contains(CGPoint(x: 420, y: 650)))
        #expect(eye.contains(CGPoint(x: 20, y: 20)))
    }

    @Test func excludesEverythingOutsideItsFrame() {
        #expect(panel.contains(CGPoint(x: 99, y: 650)) == false)
        #expect(panel.contains(CGPoint(x: 420, y: 499)) == false)
        #expect(panel.contains(CGPoint(x: 741, y: 650)) == false)
    }

    @Test func excludesTheRoundedOffBottomCornersButNotTheSquareTop() {
        // Just inside the frame's bottom-left and bottom-right corners, outside the 22 pt rounding.
        #expect(panel.contains(CGPoint(x: 102, y: 502)) == false)
        #expect(panel.contains(CGPoint(x: 738, y: 502)) == false)
        // The same distance from the top corners, which are square.
        #expect(panel.contains(CGPoint(x: 102, y: 798)))
        #expect(panel.contains(CGPoint(x: 738, y: 798)))
        // Inside the rounding of a bottom corner.
        #expect(panel.contains(CGPoint(x: 110, y: 510)))
    }

    @Test func aRoundEyeExcludesTheCornersOfItsSquare() {
        #expect(eye.contains(CGPoint(x: 11, y: 11)) == false)
        #expect(eye.contains(CGPoint(x: 29, y: 29)) == false)
        #expect(eye.contains(CGPoint(x: 20, y: 11)))
    }
}

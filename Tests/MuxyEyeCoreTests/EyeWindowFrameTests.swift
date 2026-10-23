import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct EyeWindowFrameTests {
    let eye = CGRect(x: 310, y: 978, width: 20, height: 20)
    let panel = CGRect(x: 0, y: 700, width: 640, height: 300)
    let taller = CGRect(x: 0, y: 600, width: 640, height: 400)
    /// The stage: its top is the top of the screen.
    let bounds = CGRect(x: -40, y: 500, width: 720, height: 500)
    let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant { start + .milliseconds(milliseconds) }

    @Test func atRestTheWindowIsTheFootprint() {
        let window = EyeWindowFrame(footprint: eye)
        #expect(window.frame(margin: 30, within: bounds) == eye)
        #expect(window.isMoving == false)
        #expect(window.settlesAt == nil)
    }

    @Test func whileAnimatingItCoversBothFootprintsWithAMarginBelowTheScreenTop() {
        var window = EyeWindowFrame(footprint: eye)
        window.animate(to: panel, at: start, for: .milliseconds(800))
        #expect(window.isMoving)
        #expect(window.footprint == panel)
        #expect(window.frame(margin: 30, within: bounds) == CGRect(x: -30, y: 670, width: 700, height: 330))
    }

    @Test func itShrinksOnlyOnceTheLongestAnimationIsDone() {
        var window = EyeWindowFrame(footprint: eye)
        window.animate(to: panel, at: start, for: .milliseconds(800))
        window.animate(to: eye, at: at(100), for: .milliseconds(500))
        #expect(window.settlesAt == at(800))
        let early = window.settle(at: at(700))
        #expect(early == false)
        #expect(window.frame(margin: 30, within: bounds).contains(panel))
        let done = window.settle(at: at(800))
        #expect(done)
        #expect(window.frame(margin: 30, within: bounds) == eye)
        #expect(window.isMoving == false)
    }

    @Test func aLaterAnimationPushesTheSettleBack() {
        var window = EyeWindowFrame(footprint: eye)
        window.animate(to: panel, at: start, for: .milliseconds(300))
        window.animate(to: panel, at: at(200), for: .milliseconds(400))
        #expect(window.settlesAt == at(600))
        let early = window.settle(at: at(300))
        #expect(early == false)
        let done = window.settle(at: at(600))
        #expect(done)
    }

    @Test func aJumpAtRestMovesTheWindowAtOnce() {
        var window = EyeWindowFrame(footprint: panel)
        window.jump(to: taller)
        #expect(window.isMoving == false)
        #expect(window.frame(margin: 30, within: bounds) == taller)
    }

    @Test func aJumpWhileMovingWaitsForTheMove() {
        var window = EyeWindowFrame(footprint: eye)
        window.animate(to: panel, at: start, for: .milliseconds(500))
        window.jump(to: taller)
        #expect(window.frame(margin: 0, within: bounds) == taller.union(eye))
        let done = window.settle(at: at(500))
        #expect(done)
        #expect(window.frame(margin: 30, within: bounds) == taller)
    }

    @Test func settlingAtRestChangesNothing() {
        var window = EyeWindowFrame(footprint: eye)
        let settled = window.settle(at: at(1000))
        #expect(settled == false)
        #expect(window.frame(margin: 30, within: bounds) == eye)
    }

    @Test func rapidTogglesEndOnTheLastFootprint() {
        var window = EyeWindowFrame(footprint: eye)
        for (index, target) in [panel, eye, panel, eye, panel, eye].enumerated() {
            window.animate(to: target, at: at(index * 40), for: .milliseconds(600))
        }
        #expect(window.frame(margin: 0, within: bounds) == panel.union(eye))
        let done = window.settle(at: at(5 * 40 + 600))
        #expect(done)
        #expect(window.frame(margin: 30, within: bounds) == eye)
    }
}

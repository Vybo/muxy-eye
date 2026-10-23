import Testing
@testable import MuxyEyeCore

@Suite struct PanelMotionTests {
    let motion = PanelMotion()

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func openGrowsWithASlightOvershoot() throws {
        let open = try #require(motion.shapeOpen)
        #expect(open.curve == .spring(response: 0.5, dampingFraction: 0.72))
        #expect(open.delay == 0)
        #expect(open.curve.overshoot > 0.02)
        #expect(open.curve.overshoot < 0.06)
    }

    @Test func closeFadesTheContentBeforeTheShapeShrinksWithoutOvershoot() throws {
        let shape = try #require(motion.shapeClose)
        #expect(shape.curve == .spring(response: 0.38, dampingFraction: 1))
        #expect(shape.curve.overshoot == 0)
        let out = try #require(motion.contentOut)
        #expect(close(out.totalTime, 0.12))
        #expect(shape.delay > 0)
        #expect(shape.delay < out.totalTime)
    }

    @Test func contentFadesInOnceTheShapeHasMostlyGrown() throws {
        let content = try #require(motion.contentIn)
        #expect(close(content.delay, 0.18))
        let detail = try #require(motion.detailIn)
        #expect(close(detail.delay, 0.26))
        #expect(motion.contentSlide == 6)
    }

    @Test func rowsCascadeFiftyMillisecondsApartUpToSixRows() throws {
        let delays = try (0..<9).map { try #require(motion.rowIn($0)).delay }
        #expect(close(delays[0], 0.22))
        #expect(close(delays[1], 0.27))
        #expect(close(delays[2], 0.32))
        #expect(close(delays[5], 0.47))
        #expect(delays[6...].allSatisfy { close($0, delays[5]) })
    }

    @Test func eyeLeavesAtOnceAndReturnsAsTheShapeLands() throws {
        #expect(motion.eyeOut.delay == 0)
        #expect(motion.eyeOut.totalTime <= 0.15)
        let shape = try #require(motion.shapeClose)
        // Mostly landed by the time the ring starts to show, fully shown by the time the window settles.
        let landed = shape.delay + 0.2
        #expect(motion.eyeIn.delay >= landed)
        #expect(motion.eyeIn.totalTime <= motion.closeDuration)
    }

    @Test func windowWaitsForEveryShapeAnimation() throws {
        let open = try #require(motion.shapeOpen)
        let shape = try #require(motion.shapeClose)
        #expect(motion.openDuration >= open.totalTime)
        #expect(motion.closeDuration >= shape.totalTime)
        #expect(motion.closeDuration >= motion.eyeIn.totalTime)
        #expect(motion.openDuration < 1)
        #expect(motion.closeDuration < 1)
    }

    @Test func selectionSlidesQuicklyWithoutBouncing() {
        let selection = motion.selection
        #expect(selection.delay == 0)
        #expect(selection.curve.overshoot < 0.01)
        #expect(selection.totalTime < 0.6)
    }

    @Test func detailCrossFadesQuickly() {
        #expect(motion.detailSwap.curve == .easeInOut(duration: 0.18))
        #expect(motion.detailSwap.delay == 0)
    }

    @Test func railChangesSettleWellBeforeTheNextPoll() {
        let change = motion.railChange
        #expect(change.delay == 0)
        #expect(change.curve.overshoot < 0.01)
        #expect(change.totalTime < 0.8)
    }

    @Test func wingGrowsAndRetractsWithoutAVisibleBounce() {
        let wing = motion.collapsedChange
        #expect(wing.delay == 0)
        #expect(wing.curve.overshoot * EyeLayout.wingWidth < 1)
        #expect(wing.totalTime < 0.6)
    }

    @Test func countPopsBrieflyWithinTheMotionMargin() throws {
        let pop = try #require(motion.countPop)
        #expect(pop.scale > 1.1)
        #expect(pop.scale <= 1.3)
        #expect(pop.rise < pop.fall)
        #expect(pop.totalTime <= 0.4)
        // The bumped badge must not be clipped by the window, which grows by at least 8 points.
        let overflow = (pop.scale - 1) * max(EyeLayout.badgeSize.width, EyeLayout.badgeSize.height) / 2
        #expect(overflow <= PanelMotion.overshootMargin(forTravel: 0))
    }

    @Test(arguments: [100.0, 600.0, 900.0])
    func marginCoversTheOpeningOvershoot(travel: Double) throws {
        let open = try #require(motion.shapeOpen)
        let margin = PanelMotion.overshootMargin(forTravel: travel)
        #expect(margin >= open.curve.overshoot * travel)
        #expect(margin >= 8)
    }
}

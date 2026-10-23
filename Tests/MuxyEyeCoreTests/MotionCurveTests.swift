import Testing
@testable import MuxyEyeCore

@Suite struct MotionCurveTests {
    /// The remaining fraction of a spring's travel over time, by stepping its equation of motion,
    /// so the closed forms under test are checked against something independent of them.
    private func simulate(response: Double, damping: Double, until end: Double) -> [(time: Double, offset: Double)] {
        let omega = 2 * Double.pi / response
        let step = 1e-5
        var offset = 1.0
        var velocity = 0.0
        var time = 0.0
        var samples: [(time: Double, offset: Double)] = []
        var index = 0
        while time <= end {
            velocity += (-omega * omega * offset - 2 * damping * omega * velocity) * step
            offset += velocity * step
            time += step
            index += 1
            if index % 50 == 0 { samples.append((time, offset)) }
        }
        return samples
    }

    @Test func overshootMatchesTheSpring() throws {
        let curve = MotionCurve.spring(response: 0.5, dampingFraction: 0.72)
        let deepest = try #require(simulate(response: 0.5, damping: 0.72, until: 1).map(\.offset).min())
        #expect(abs(-deepest - curve.overshoot) < 0.002)
        #expect(MotionCurve.spring(response: 0.38, dampingFraction: 1).overshoot == 0)
        #expect(MotionCurve.easeOut(duration: 0.2).overshoot == 0)
    }

    @Test(arguments: [(0.5, 0.72), (0.38, 1.0), (0.35, 0.8), (0.3, 1.4)])
    func springsStayWithinPrecisionOnceSettled(response: Double, damping: Double) {
        let curve = MotionCurve.spring(response: response, dampingFraction: damping)
        let settled = curve.settlingTime(precision: 0.001)
        let samples = simulate(response: response, damping: damping, until: settled + 1)
        #expect(samples.filter { $0.time >= settled }.allSatisfy { abs($0.offset) <= 0.001 })
        // Not wildly cautious either: the spring is still visibly moving a little earlier.
        #expect(samples.contains { $0.time >= settled - 0.1 && abs($0.offset) > 0.0005 })
    }

    @Test(arguments: [0.0, -0.5])
    func springsThatNeverSettleStopAtTheLongestTime(damping: Double) {
        let curve = MotionCurve.spring(response: 0.5, dampingFraction: damping)
        #expect(curve.settlingTime() == MotionCurve.longestSettlingTime)
    }

    @Test func aDegenerateResponseStopsAtTheLongestTime() {
        #expect(MotionCurve.spring(response: 0, dampingFraction: 1).settlingTime() == MotionCurve.longestSettlingTime)
    }

    @Test func anExtremePrecisionStillStopsAtTheLongestTime() {
        let curve = MotionCurve.spring(response: 0.5, dampingFraction: 0.72)
        #expect(curve.settlingTime(precision: 1e-300) == MotionCurve.longestSettlingTime)
    }

    @Test func timedCurvesSettleAtTheirDuration() {
        #expect(MotionCurve.easeOut(duration: 0.12).settlingTime() == 0.12)
        #expect(MotionCurve.easeInOut(duration: 0.2).settlingTime() == 0.2)
        #expect(MotionCurve.decelerate(duration: 0.35).settlingTime() == 0.35)
    }

    @Test func motionTimeIncludesItsDelay() {
        let motion = Motion(.easeOut(duration: 0.2), delay: 0.18)
        #expect(abs(motion.totalTime - 0.38) < 1e-9)
        #expect(Motion(.easeOut(duration: 0.12)).delay == 0)
    }
}

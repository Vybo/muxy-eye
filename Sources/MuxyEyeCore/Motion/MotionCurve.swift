import Foundation

/// The timing of one animated change, in terms the app maps onto SwiftUI animations.
public enum MotionCurve: Sendable, Equatable {
    /// A spring. `response` is the period of the undamped spring in seconds; `dampingFraction` 1 is
    /// critically damped (no overshoot), below 1 it overshoots.
    case spring(response: Double, dampingFraction: Double)
    /// Starts fast and slows down.
    case easeOut(duration: Double)
    case easeInOut(duration: Double)
    /// A strong deceleration, CSS `cubic-bezier(.2, .8, .2, 1)`.
    case decelerate(duration: Double)

    /// The longest settling time reported. A spring without damping never settles, and an extreme
    /// precision would take minutes to reach; both stop here.
    public static let longestSettlingTime: Double = 10

    /// How far past its target the change goes, as a fraction of the distance it travels.
    public var overshoot: Double {
        guard case .spring(_, let damping) = self, damping < 1 else { return 0 }
        return exp(-damping * .pi / (1 - damping * damping).squareRoot())
    }

    /// Seconds until the change is within `precision` of its target, as a fraction of the distance,
    /// and stays there. A spring is bounded by the envelope of its decay; timed curves end on time.
    public func settlingTime(precision: Double = 0.001) -> Double {
        switch self {
        case .easeOut(let duration), .easeInOut(let duration), .decelerate(let duration):
            return duration
        case .spring(let response, let damping):
            guard response > 0, damping > 0 else { return Self.longestSettlingTime }
            let omega = 2 * Double.pi / response
            let envelope: (Double) -> Double
            if damping < 1 {
                let scale = 1 / (1 - damping * damping).squareRoot()
                envelope = { scale * exp(-damping * omega * $0) }
            } else if damping == 1 {
                envelope = { (1 + omega * $0) * exp(-omega * $0) }
            } else {
                let spread = (damping * damping - 1).squareRoot()
                let slow = omega * (damping - spread)
                let fast = omega * (damping + spread)
                envelope = { fast / (fast - slow) * exp(-slow * $0) }
            }
            let step = 1.0 / 240
            var time = 0.0
            while envelope(time) > precision, time < Self.longestSettlingTime { time += step }
            return min(time, Self.longestSettlingTime)
        }
    }
}

/// A curve and how long after the change it starts.
public struct Motion: Sendable, Equatable {
    public var curve: MotionCurve
    public var delay: Double

    public init(_ curve: MotionCurve, delay: Double = 0) {
        self.curve = curve
        self.delay = delay
    }

    /// Seconds from the change until the motion has settled.
    public var totalTime: Double { delay + curve.settlingTime() }
}

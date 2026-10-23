import CoreGraphics
import Foundation

public enum SignalLineGeometry {
    /// Sample points of a sine line (`morph` 0) that morphs into a ring (`morph` 1).
    public static func points(
        diameter: CGFloat,
        phase: Double,
        amplitude: CGFloat,
        morph: CGFloat,
        samples: Int
    ) -> [CGPoint] {
        guard samples > 1 else { return [] }
        let center = diameter / 2
        let radius = 0.28 * diameter
        let steps = CGFloat(samples - 1)
        return (0..<samples).map { index in
            let t = CGFloat(index) / steps
            let lineX = diameter * (0.1 + 0.8 * t)
            let lineY = center + amplitude * CGFloat(sin(Double(2 * .pi * lineX / (0.8 * diameter)) + phase))
            let angle = 2 * CGFloat.pi * t
            let ringX = center + radius * cos(angle)
            let ringY = center + radius * sin(angle)
            return CGPoint(x: lineX + (ringX - lineX) * morph, y: lineY + (ringY - lineY) * morph)
        }
    }
}

import CoreGraphics
import Testing
@testable import MuxyEyeCore

@Suite struct SignalLineGeometryTests {
    @Test func morphEndpoints() {
        let line = SignalLineGeometry.points(diameter: 100, phase: 0.7, amplitude: 3, morph: 0, samples: 32)
        #expect(line.count == 32)
        #expect(line.allSatisfy { abs($0.y - 50) <= 3 + 0.001 })
        let ring = SignalLineGeometry.points(diameter: 100, phase: 0.7, amplitude: 3, morph: 1, samples: 32)
        #expect(ring.allSatisfy { abs(hypot($0.x - 50, $0.y - 50) - 28) <= 0.001 })
    }
}

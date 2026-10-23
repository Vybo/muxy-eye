import SwiftUI

enum PanelTheme {
    private static let lineHex: UInt32 = 0xFFFFFF
    private static let waitingHex: UInt32 = 0xFF9F0A

    static let eye = Color(hex: 0x000000)
    static let line = Color(hex: lineHex)
    static let secondaryLine = Color(hex: 0x5AC8FA)
    static let secondaryLineOpacity: Double = 0.55
    static let waiting = Color(hex: waitingHex)

    static let background = Color(hex: 0x000000)
    static let card = Color(hex: 0x1C1C1E)
    static let divider = Color(hex: 0x2C2C2E)
    static let text = Color(hex: 0xF5F5F7)
    static let secondaryText = Color(hex: 0x8E8E93)
    static let link = Color(hex: 0x0A84FF)

    /// The signal line's colour along the line → ring morph: `line` at 0, `waiting` at 1.
    static func lineColor(morph: CGFloat) -> Color {
        let fraction = Double(min(max(morph, 0), 1))
        func channel(_ shift: UInt32) -> Double {
            let from = Double((lineHex >> shift) & 0xFF)
            let to = Double((waitingHex >> shift) & 0xFF)
            return (from + (to - from) * fraction) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0))
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

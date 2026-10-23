import MuxyEyeCore
import SwiftUI

/// A read-only excerpt of the terminal, for a waiting session without hook content
/// (another agent, or a Claude prompt the eye has no details for).
struct ScreenFallbackView: View {
    let screen: String?

    var body: some View {
        let lines = screen.map { SessionPresentation.screenTail($0) } ?? []
        if lines.isEmpty {
            Text(screen == nil ? "Reading the terminal…" : "The terminal is empty.")
                .font(.system(size: 12))
                .foregroundStyle(PanelTheme.secondaryText)
        } else {
            MonospaceCard {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }
}

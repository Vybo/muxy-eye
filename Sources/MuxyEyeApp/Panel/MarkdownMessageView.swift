import MuxyEyeCore
import SwiftUI

/// A message's markdown blocks: paragraphs, headings, lists, code, quotes and rules.
struct MarkdownMessageView: View {
    private static let bodySize: CGFloat = 12.5
    private static let listIndent: CGFloat = 14
    private static let markerWidth: CGFloat = 16

    let blocks: [MarkdownBlock]

    init(_ text: String) {
        blocks = MarkdownBlocks.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .foregroundStyle(PanelTheme.text)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inline(text)
        case .heading(let level, let text):
            let size = Self.headingSize(level)
            InlineMarkdown.text(text, fontSize: size)
                .font(.system(size: size, weight: .semibold))
                .padding(.top, 2)
        case .listItem(let depth, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: Self.label(for: marker))
                    .font(.system(size: Self.bodySize))
                    .monospacedDigit()
                    .foregroundStyle(PanelTheme.secondaryText)
                    .frame(width: Self.markerWidth, alignment: .trailing)
                inline(text)
            }
            .padding(.leading, CGFloat(depth) * Self.listIndent)
        case .codeBlock(_, let code):
            Text(verbatim: code.isEmpty ? " " : code)
                .font(.system(size: Self.bodySize - 1, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PanelTheme.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(PanelTheme.divider))
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(PanelTheme.secondaryText.opacity(0.6)).frame(width: 2)
                inline(text).foregroundStyle(PanelTheme.secondaryText)
            }
        case .rule:
            Rectangle().fill(PanelTheme.secondaryText.opacity(0.4)).frame(height: 1).padding(.vertical, 4)
        }
    }

    private func inline(_ text: String) -> some View {
        InlineMarkdown.text(text, fontSize: Self.bodySize)
            .font(.system(size: Self.bodySize))
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 15
        case 2: 13.5
        default: bodySize
        }
    }

    private static func label(for marker: MarkdownListMarker) -> String {
        switch marker {
        case .bullet: "•"
        case .number(let number): "\(number)."
        }
    }
}

import SwiftUI

/// Renders inline markdown (bold, italic, code, strikethrough, links) for Claude's text. Text that
/// doesn't parse is shown as written.
enum InlineMarkdown {
    /// Inline code sits on a slightly lighter patch than the card behind it.
    static let codeBackground = PanelTheme.divider

    /// - Parameters:
    ///   - fontSize: the size of the surrounding text, which inline code follows.
    ///   - codeBackground: the patch behind inline code.
    ///   - links: whether links are links; inside a button they stay plain text, so a tap can only
    ///     ever be the answer.
    static func text(
        _ source: String,
        fontSize: CGFloat,
        codeBackground: Color = codeBackground,
        links: Bool = true
    ) -> Text {
        Text(attributed(source, fontSize: fontSize, codeBackground: codeBackground, links: links))
    }

    static func attributed(
        _ source: String,
        fontSize: CGFloat,
        codeBackground: Color = codeBackground,
        links: Bool = true
    ) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var result = try? AttributedString(markdown: source, options: options) else {
            return AttributedString(source)
        }
        for run in result.runs {
            let range = run.range
            if run.inlinePresentationIntent?.contains(.code) == true {
                result[range].font = .system(size: fontSize - 1, design: .monospaced)
                result[range].backgroundColor = codeBackground
            }
            guard let url = run.link else { continue }
            if links, isOpenable(url) {
                result[range].foregroundColor = PanelTheme.link
                result[range].underlineStyle = .single
            } else {
                result[range].link = nil
            }
        }
        return result
    }

    /// Only web links open; Claude's text can't launch other apps or files.
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

import AppKit
import MuxyEyeCore
import SwiftUI

/// Renders inline markdown (bold, italic, code, strikethrough, links) for Claude's text. Text that
/// doesn't parse is shown as written.
@MainActor
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

    /// Built once per distinct input: panel bodies re-evaluate often, and parsing is not free.
    static func attributed(
        _ source: String,
        fontSize: CGFloat,
        codeBackground: Color = codeBackground,
        links: Bool = true
    ) -> AttributedString {
        let key = CacheKey(source: source, fontSize: fontSize, codeBackground: codeBackground, links: links)
        if let cached = cache.object(forKey: key) { return cached.value }
        let built = build(source, fontSize: fontSize, codeBackground: codeBackground, links: links)
        cache.setObject(Box(built), forKey: key)
        return built
    }

    private static let cache: NSCache<CacheKey, Box> = {
        let cache = NSCache<CacheKey, Box>()
        cache.countLimit = 256
        return cache
    }()

    private final class Box {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private final class CacheKey: NSObject {
        let source: String
        let fontSize: CGFloat
        let codeBackground: Color
        let links: Bool

        init(source: String, fontSize: CGFloat, codeBackground: Color, links: Bool) {
            self.source = source
            self.fontSize = fontSize
            self.codeBackground = codeBackground
            self.links = links
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(source)
            hasher.combine(fontSize)
            hasher.combine(links)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return source == other.source && fontSize == other.fontSize
                && codeBackground == other.codeBackground && links == other.links
        }
    }

    private static func build(
        _ source: String,
        fontSize: CGFloat,
        codeBackground: Color,
        links: Bool
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
            if LinkPolicy.keeps(url, linksEnabled: links) {
                result[range].foregroundColor = PanelTheme.link
                result[range].underlineStyle = .single
            } else {
                result[range].link = nil
            }
        }
        return result
    }
}

extension View {
    /// Every link click in Claude's text is checked again here, whatever the attributed string
    /// holds: web links open in the default browser, anything else is swallowed.
    func openingOnlyWebLinks() -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard LinkPolicy.isOpenable(url) else { return .handled }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}

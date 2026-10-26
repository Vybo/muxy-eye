import Foundation


/// How a list item is marked.
public enum MarkdownListMarker: Sendable, Equatable {
    case bullet
    case number(Int)
}

/// One block of a markdown message. The text of a block is still inline markdown.
public enum MarkdownBlock: Sendable, Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    /// A list item; `depth` is 0, or 1 for an item nested under another.
    case listItem(depth: Int, marker: MarkdownListMarker, text: String)
    case codeBlock(language: String?, code: String)
    case quote(String)
    case rule
}

/// Splits a message into the block formatting the panel shows: paragraphs, headings, lists (one
/// nesting level), fenced code, block quotes and rules. Anything else stays a paragraph.
public enum MarkdownBlocks {
    private static let fence = "```"
    private static let nestingIndent = 2
    private static let tabWidth = 4
    private static let maxHeadingLevel = 6

    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix(fence) {
                index = codeBlock(in: lines, from: index, into: &blocks)
            } else if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
            } else if let heading = heading(trimmed) {
                blocks.append(heading)
                index += 1
            } else if quoteContent(trimmed) != nil {
                index = quote(in: lines, from: index, into: &blocks)
            } else if let item = listItem(line) {
                index = list(in: lines, from: index, first: item, into: &blocks)
            } else {
                index = paragraph(in: lines, from: index, into: &blocks)
            }
        }
        return blocks
    }

    // MARK: Multi-line blocks

    private static func codeBlock(in lines: [String], from start: Int, into blocks: inout [MarkdownBlock]) -> Int {
        let opening = lines[start].trimmingCharacters(in: .whitespaces)
        let language = String(opening.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
        var code: [String] = []
        var index = start + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                index += 1
                break
            }
            code.append(lines[index])
            index += 1
        }
        blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")))
        return index
    }

    private static func quote(in lines: [String], from start: Int, into blocks: inout [MarkdownBlock]) -> Int {
        var content: [String] = []
        var index = start
        while index < lines.count, let line = quoteContent(lines[index].trimmingCharacters(in: .whitespaces)) {
            content.append(line)
            index += 1
        }
        blocks.append(.quote(content.joined(separator: "\n")))
        return index
    }

    private static func list(
        in lines: [String],
        from start: Int,
        first: ListLine,
        into blocks: inout [MarkdownBlock]
    ) -> Int {
        var item = first
        var index = start + 1
        func flush() {
            blocks.append(.listItem(depth: item.depth, marker: item.marker, text: item.text))
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let next = listItem(line), !isRule(trimmed) {
                flush()
                item = next
            } else if !trimmed.isEmpty, indentation(of: line) > 0, !startsBlock(line) {
                item.text += "\n" + trimmed
            } else {
                break
            }
            index += 1
        }
        flush()
        return index
    }

    private static func paragraph(in lines: [String], from start: Int, into blocks: inout [MarkdownBlock]) -> Int {
        var content = [lines[start].trimmingCharacters(in: .whitespaces)]
        var index = start + 1
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty, !startsBlock(lines[index]) {
            content.append(lines[index].trimmingCharacters(in: .whitespaces))
            index += 1
        }
        blocks.append(.paragraph(content.joined(separator: "\n")))
        return index
    }

    // MARK: Single lines

    private struct ListLine {
        let depth: Int
        let marker: MarkdownListMarker
        var text: String
    }

    /// Whether a line begins a block of its own, ending a paragraph or a list item's continuation.
    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(fence) || isRule(trimmed) || heading(trimmed) != nil
            || quoteContent(trimmed) != nil || listItem(line) != nil
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...maxHeadingLevel).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: hashes, text: text)
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// The text after the `>` of a quote line, or nil when the line isn't one.
    private static func quoteContent(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix(">") else { return nil }
        let rest = trimmed.dropFirst()
        return (rest.hasPrefix(" ") ? rest.dropFirst() : rest).trimmingCharacters(in: .whitespaces)
    }

    private static func listItem(_ line: String) -> ListLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let depth = indentation(of: line) >= nestingIndent ? 1 : 0
        if let first = trimmed.first, "-*+".contains(first), let text = itemText(after: 1, in: trimmed) {
            return ListLine(depth: depth, marker: .bullet, text: text)
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, ".)".contains(delimiter),
              let text = itemText(after: digits.count + 1, in: trimmed)
        else { return nil }
        return ListLine(depth: depth, marker: .number(number), text: text)
    }

    /// The item's text after a marker of `length` characters, which a space must follow.
    private static func itemText(after length: Int, in trimmed: String) -> String? {
        let rest = trimmed.dropFirst(length)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func indentation(of line: String) -> Int {
        var width = 0
        for character in line {
            switch character {
            case " ": width += 1
            case "\t": width += tabWidth
            default: return width
            }
        }
        return width
    }
}

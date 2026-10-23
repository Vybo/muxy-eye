import Foundation


public enum ScreenParser {
    private struct OptionLine {
        var number: Int
        var label: String
        var labelColumn: Int
        var isCursor: Bool
        var checked: Bool?
    }

    public static func parse(_ screen: String) -> ScreenPrompt? {
        let lines = splitLines(screen)
        let width = lines.map(\.count).max() ?? 0

        guard let first = lines.lastIndex(where: { optionLine($0)?.number == 1 }) else { return nil }
        guard let start = (0..<first).reversed().first(where: { isRule(lines[$0]) }) else { return nil }
        let footer = lines[first...].firstIndex { $0.contains("Esc to cancel") || $0.contains("Enter to select") }
        let end = footer ?? lines.count
        let block = Array(lines[start..<end])
        let firstInBlock = first - start

        let isReview = block[..<firstInBlock].contains { $0.contains("Ready to submit your answers?") }
        if footer == nil && !isReview { return nil }

        let headerIndex = block[1..<max(firstInBlock, 1)].firstIndex { !trimmed($0).isEmpty }
            .flatMap { index in (block[index].contains("☐") || block[index].contains("☒")) ? index : nil }
        let options = collectOptions(Array(block[firstInBlock...]), joinWrapped: !isReview && headerIndex == nil, width: width)

        if isReview { return .submitReview(options: options) }

        if let headerIndex {
            let header = headerText(block[headerIndex])
            let question = block[(headerIndex + 1)...].map(trimmed).first { !$0.isEmpty } ?? ""
            return .question(
                header: header,
                question: question,
                options: options,
                isMultiSelect: options.contains { $0.checked != nil }
            )
        }

        let titleIndex = (1..<max(firstInBlock, 1)).first { !trimmed(block[$0]).isEmpty }
        guard let titleIndex else { return nil }
        guard let questionIndex = (titleIndex + 1..<firstInBlock).last(where: {
            let t = trimmed(block[$0])
            return !t.isEmpty && !isRule(block[$0])
        }) else { return nil }
        let body = block[(titleIndex + 1)..<questionIndex]
            .filter { !isDashed($0) && !trimmed($0).hasPrefix("Tip:") }
            .map(trimmed)
            .joined(separator: "\n")
        return .permission(
            title: trimmed(block[titleIndex]),
            body: body,
            question: trimmed(block[questionIndex]),
            options: options
        )
    }

    public static func isAtIdlePrompt(_ screen: String) -> Bool {
        guard parse(screen) == nil else { return false }
        let lines = splitLines(screen)
        guard let index = lines.lastIndex(where: { trimmed($0).hasPrefix("❯") }),
              trimmed(lines[index]) == "❯",
              index > 0,
              isRule(lines[index - 1])
        else { return false }
        return true
    }

    // MARK: - Helpers

    private static func splitLines(_ screen: String) -> [[Character]] {
        screen.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
            var chars = Array(line)
            while let last = chars.last, last.isWhitespace { chars.removeLast() }
            return chars
        }
    }

    private static func trimmed(_ line: [Character]) -> String {
        String(line).trimmingCharacters(in: .whitespaces)
    }

    private static func isRule(_ line: [Character]) -> Bool {
        let t = line.drop { $0 == " " }
        return t.count >= 20 && t.allSatisfy { $0 == "─" }
    }

    private static func isDashed(_ line: [Character]) -> Bool {
        let t = line.drop { $0 == " " }
        return !t.isEmpty && t.allSatisfy { $0 == "╌" }
    }

    private static func headerText(_ line: [Character]) -> String {
        guard let marker = line.lastIndex(where: { $0 == "☐" || $0 == "☒" }) else { return "" }
        var text = String(line[(marker + 1)...])
        if let range = text.range(of: "  ") { text = String(text[..<range.lowerBound]) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func optionLine(_ line: [Character]) -> OptionLine? {
        var i = 0
        func skipSpaces() { while i < line.count, line[i] == " " { i += 1 } }
        skipSpaces()
        var cursor = false
        if i < line.count, line[i] == "❯" {
            cursor = true
            i += 1
            skipSpaces()
        }
        let digitsStart = i
        while i < line.count, line[i].isASCII, line[i].isNumber { i += 1 }
        guard i > digitsStart, let number = Int(String(line[digitsStart..<i])) else { return nil }
        guard i < line.count, line[i] == "." else { return nil }
        i += 1
        let spacesStart = i
        skipSpaces()
        guard i > spacesStart else { return nil }
        var checked: Bool?
        if i + 2 < line.count, line[i] == "[", line[i + 2] == "]", line[i + 1] == " " || line[i + 1] == "✔" {
            checked = line[i + 1] == "✔"
            i += 3
            let afterBox = i
            skipSpaces()
            guard i > afterBox else { return nil }
        }
        guard i < line.count else { return nil }
        return OptionLine(
            number: number,
            label: String(line[i...]),
            labelColumn: i,
            isCursor: cursor,
            checked: checked
        )
    }

    private static func collectOptions(_ block: [[Character]], joinWrapped: Bool, width: Int) -> [ScreenOption] {
        var options: [ScreenOption] = []
        var column = 0
        var previousLength = 0
        var continued = false
        for line in block {
            if let option = optionLine(line) {
                options.append(ScreenOption(
                    number: option.number,
                    label: option.label,
                    description: nil,
                    isCursor: option.isCursor,
                    checked: option.checked
                ))
                column = option.labelColumn
                previousLength = line.count
                continued = true
                continue
            }
            let text = trimmed(line)
            guard continued, !text.isEmpty, !isRule(line) else { continue }
            let indent = line.prefix { $0 == " " }.count
            guard indent >= column else { continue }
            if joinWrapped {
                let separator = previousLength == width ? "" : " "
                options[options.count - 1].label += separator + text
            } else {
                let existing = options[options.count - 1].description
                options[options.count - 1].description = existing.map { $0 + " " + text } ?? text
            }
            previousLength = line.count
        }
        return options
    }
}

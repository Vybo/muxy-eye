import Foundation

/// Cleans text the user typed before it is typed into a terminal, so it can never press
/// Enter, Escape or another key by itself.
public enum AnswerText {
    /// Line breaks and tabs become single spaces, other control characters (ESC included) are
    /// removed, and the ends are trimmed. Returns nil when nothing is left to send.
    public static func sanitized(_ text: String) -> String? {
        var result = ""
        var lastWasBreak = false
        for character in text {
            if character.isNewline {
                if !lastWasBreak { result.append(" ") }
                lastWasBreak = true
                continue
            }
            if character == "\t" {
                result.append(" ")
                lastWasBreak = false
                continue
            }
            let kept = character.unicodeScalars.filter { $0.properties.generalCategory != .control }
            guard !kept.isEmpty else { continue }
            result.unicodeScalars.append(contentsOf: kept)
            lastWasBreak = false
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UserAnswer {
    /// The answer with its text sanitized, or nil when the text is empty afterwards.
    public var sanitized: UserAnswer? {
        switch self {
        case .option, .multiSelect: self
        case .deny(let feedback): AnswerText.sanitized(feedback).map { .deny(feedback: $0) }
        case .freeText(let text): AnswerText.sanitized(text).map { .freeText($0) }
        case .reply(let text): AnswerText.sanitized(text).map { .reply($0) }
        }
    }
}

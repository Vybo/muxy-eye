import Foundation

public enum NamedKey: String, Sendable {
    case enter = "Enter"
    case tab = "Tab"
    case escape = "Escape"
    case backspace = "Backspace"
}

public enum UserAnswer: Sendable, Equatable {
    case option(Int)
    case deny(feedback: String)
    case freeText(String)
    case multiSelect(Set<Int>)
    case reply(String)
}

public enum AnswerStep: Sendable, Equatable {
    case text(String)
    case key(NamedKey)
    case expectIdlePrompt
    case expectSubmitReview
    /// Wait until `question` shows its empty "Type something" row, numbered `option`, as the cursor row.
    case expectFreeTextField(option: Int, question: String)
}

public enum AnswerRejection: Error, Sendable, Equatable {
    case promptChanged
    case unsupported
    case noMatchingOption
}

extension QuestionRequest {
    /// The question the terminal is showing now; Claude asks several questions one after another.
    public func current(on screen: ScreenPrompt?) -> Question? {
        guard case .question(_, let text, _, _)? = screen else { return nil }
        return questions.first { AnswerPlanner.isSameQuestion($0.question, text) }
    }
}

public enum AnswerPlanner {
    static let arrowRight = "\u{1B}[C"

    private static let fileTools: Set<String> = ["Write", "Edit", "MultiEdit"]

    /// Whether the screen still shows the prompt of `pending`; answers are offered only when it does.
    public static func matches(_ pending: PendingItem, screen: ScreenPrompt?, idlePrompt: Bool) -> Bool {
        switch pending.kind {
        case .finished:
            return idlePrompt
        case .permission(let request):
            guard case .permission(let title, let body, _, _)? = screen else { return false }
            return permissionMatches(request, title: title, body: body)
        case .question(let request):
            guard case .question(_, _, let options, _)? = screen,
                  let question = request.current(on: screen)
            else { return false }
            let labels = options.map(\.label)
            let expected = question.options.map(\.label)
            return labels.count >= expected.count && Array(labels.prefix(expected.count)) == expected
        }
    }

    static func steps(
        for answer: UserAnswer,
        pending: PendingItem,
        screen: ScreenPrompt?,
        idlePrompt: Bool
    ) -> Result<[AnswerStep], AnswerRejection> {
        guard matches(pending, screen: screen, idlePrompt: idlePrompt) else { return .failure(.promptChanged) }

        if case .reply(let text) = answer {
            guard case .finished = pending.kind else { return .failure(.promptChanged) }
            return .success([.text(text), .key(.enter)])
        }
        if case .finished = pending.kind { return .failure(.promptChanged) }

        guard let screen, let (options, isMulti) = optionsAndMode(of: screen) else { return .failure(.promptChanged) }

        switch answer {
        case .option(let n):
            guard !isMulti, options.contains(where: { $0.number == n }) else {
                return .failure(isMulti ? .unsupported : .noMatchingOption)
            }
            return .success([.text(String(n))])
        case .deny(let feedback):
            guard case .permission = pending.kind else { return .failure(.unsupported) }
            guard let no = denyOption(on: screen) else { return .failure(.noMatchingOption) }
            return .success([.text(String(no.number)), .expectIdlePrompt, .text(feedback), .key(.enter)])
        case .freeText(let text):
            guard !isMulti, case .question = pending.kind,
                  case .question(_, let question, _, _) = screen
            else { return .failure(.unsupported) }
            guard let row = freeTextOption(on: screen) else { return .failure(.noMatchingOption) }
            return .success([
                .text(String(row.number)),
                .expectFreeTextField(option: row.number, question: question),
                .text(text),
                .key(.enter)
            ])
        case .multiSelect(let selected):
            guard isMulti, case .question(let request) = pending.kind,
                  let question = request.current(on: screen)
            else { return .failure(.unsupported) }
            let count = question.options.count
            guard selected.allSatisfy({ (1...max(count, 1)).contains($0) }) else { return .failure(.noMatchingOption) }
            var steps: [AnswerStep] = []
            for option in options where option.number <= count {
                if (option.checked ?? false) != selected.contains(option.number) {
                    steps.append(.text(String(option.number)))
                }
            }
            steps.append(contentsOf: [.text(arrowRight), .expectSubmitReview, .text("1")])
            return .success(steps)
        case .reply:
            return .failure(.promptChanged)
        }
    }

    /// A question's "Type something" row, which takes free text.
    public static func freeTextOption(on screen: ScreenPrompt?) -> ScreenOption? {
        guard case .question(_, _, let options, _)? = screen else { return nil }
        return options.first { $0.label.hasPrefix("Type something") }
    }

    /// Whether `question` is on screen with its "Type something" row `option` focused and still empty,
    /// so typed text goes into that field and nowhere else.
    public static func isFreeTextFieldOpen(option: Int, question: String, on screen: ScreenPrompt?) -> Bool {
        guard case .question(_, let text, _, _)? = screen, isSameQuestion(text, question),
              let row = freeTextOption(on: screen)
        else { return false }
        return row.number == option && row.isCursor
    }

    /// A permission prompt's "No" row, which lets the user tell Claude what to do instead.
    public static func denyOption(on screen: ScreenPrompt?) -> ScreenOption? {
        guard case .permission(_, _, _, let options)? = screen else { return nil }
        return options.first { $0.label == "No" || $0.label.hasPrefix("No,") }
    }

    private static func optionsAndMode(of screen: ScreenPrompt) -> ([ScreenOption], Bool)? {
        switch screen {
        case .permission(_, _, _, let options): (options, false)
        case .question(_, _, let options, let isMulti): (options, isMulti)
        case .submitReview: nil
        }
    }

    private static func permissionMatches(_ request: PermissionRequest, title: String, body: String) -> Bool {
        guard let primary = request.primaryText, !squash(primary).isEmpty else {
            return squash(title + body).contains(squash(request.toolName))
        }
        let target = squash(primary)
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { squash(String($0)) }
        if fileTools.contains(request.toolName) {
            return lines.contains { !$0.isEmpty && (target == $0 || target.hasSuffix("/" + $0)) }
        }
        for i in lines.indices {
            var joined = ""
            for j in i..<lines.count {
                joined += lines[j]
                if joined == target { return true }
                if joined.count >= target.count { break }
            }
        }
        return false
    }

    /// Whether two question texts are the same question, whole: the terminal wraps a long question at
    /// its width, inside a word when the word is longer than a line, so all whitespace is ignored.
    static func isSameQuestion(_ a: String, _ b: String) -> Bool {
        squash(a) == squash(b)
    }

    private static func squash(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }
}

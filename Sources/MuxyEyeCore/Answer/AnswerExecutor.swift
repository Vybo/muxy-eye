import Foundation

public enum AnswerOutcome: Sendable, Equatable {
    case delivered
    case promptChanged
    case unsupported
    case notConfirmed
    case busy
    case failed(String)
}

public actor AnswerExecutor {
    private let muxy: any MuxyControlling
    private let stepDelay: Duration
    private let confirmTimeout: Duration
    private let pollEvery: Duration
    private var inFlight: Set<MuxySessionID> = []

    public init(
        muxy: any MuxyControlling,
        stepDelay: Duration = .milliseconds(150),
        confirmTimeout: Duration = .seconds(3),
        pollEvery: Duration = .milliseconds(250)
    ) {
        self.muxy = muxy
        self.stepDelay = stepDelay
        self.confirmTimeout = confirmTimeout
        self.pollEvery = pollEvery
    }

    public func perform(_ answer: UserAnswer, pending: PendingItem, session: MuxySessionID) async -> AnswerOutcome {
        guard inFlight.insert(session).inserted else { return .busy }
        defer { inFlight.remove(session) }
        do {
            return try await run(answer, pending: pending, session: session)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func run(_ answer: UserAnswer, pending: PendingItem, session: MuxySessionID) async throws -> AnswerOutcome {
        let screen = try await muxy.readScreenState(session)
        let prompt = ScreenParser.parse(screen.text)
        let plan = AnswerPlanner.steps(
            for: answer,
            pending: pending,
            screen: prompt,
            idlePrompt: screen.isAtIdlePrompt
        )
        let steps: [AnswerStep]
        switch plan {
        case .success(let planned): steps = planned
        case .failure(.promptChanged), .failure(.noMatchingOption): return .promptChanged
        case .failure(.unsupported): return .unsupported
        }

        var lastWasKeystroke = false
        for step in steps {
            switch step {
            case .text(let text):
                if lastWasKeystroke { try await pauseBetweenSteps() }
                try await muxy.send(session, text: text)
                lastWasKeystroke = true
            case .key(let key):
                if lastWasKeystroke { try await pauseBetweenSteps() }
                try await muxy.sendKey(session, key)
                lastWasKeystroke = true
            case .expectIdlePrompt:
                guard try await waitForScreen(session, { $0.isAtIdlePrompt }) else { return .notConfirmed }
                lastWasKeystroke = false
            case .expectSubmitReview:
                let reached = try await waitForScreen(session) {
                    if case .submitReview? = ScreenParser.parse($0.text) { return true }
                    return false
                }
                guard reached else { return .notConfirmed }
                lastWasKeystroke = false
            case .expectFreeTextField(let option, let question):
                let opened = try await waitForScreen(session) {
                    AnswerPlanner.isFreeTextFieldOpen(option: option, question: question, on: ScreenParser.parse($0.text))
                }
                guard opened else { return .notConfirmed }
                lastWasKeystroke = false
            }
        }

        return try await confirm(answer, answeredQuestion: answeredQuestion(pending, on: prompt, steps: steps), session: session)
            ? .delivered : .notConfirmed
    }

    /// The question text an answer went to, when the pending item is a question. Nil when the answer
    /// itself passes through the review screen (multi-select), so seeing the review proves nothing.
    private func answeredQuestion(_ pending: PendingItem, on prompt: ScreenPrompt?, steps: [AnswerStep]) -> String? {
        guard case .question = pending.kind,
              case .question(_, let text, _, _)? = prompt,
              !steps.contains(.expectSubmitReview)
        else { return nil }
        return text
    }

    private func pauseBetweenSteps() async throws {
        if stepDelay != .zero { try await Task.sleep(for: stepDelay) }
    }

    private func waitForScreen(_ session: MuxySessionID, _ condition: (ScreenState) -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + confirmTimeout
        while true {
            if condition(try await muxy.readScreenState(session)) { return true }
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: pollEvery)
        }
    }

    /// Waits for Muxy to leave `blocked` (or reach `working` for typed prompts). An answer to one of
    /// several questions also counts once the screen moves on to another question or the review.
    private func confirm(_ answer: UserAnswer, answeredQuestion: String?, session: MuxySessionID) async throws -> Bool {
        let needsWorking: Bool
        switch answer {
        case .reply, .deny: needsWorking = true
        default: needsWorking = false
        }
        let deadline = ContinuousClock.now + confirmTimeout
        while true {
            let state = try await muxy.activity().agents.first { $0.session == session }?.state
            if needsWorking ? state == .working : state != .blocked { return true }
            if let answeredQuestion, try await screenMovedPast(answeredQuestion, session: session) { return true }
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: pollEvery)
        }
    }

    private func screenMovedPast(_ question: String, session: MuxySessionID) async throws -> Bool {
        switch ScreenParser.parse(try await muxy.readScreenState(session).text) {
        case .question(_, let text, _, _)?: text != question
        case .submitReview?: true
        default: false
        }
    }
}

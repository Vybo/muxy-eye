/// When a prompt's answers may be taken: only once the prompt has fully faded in, so the eye answers
/// only what the user has seen. Arrows and Esc don't answer and aren't held.
public struct AnswerGate: Sendable, Equatable {
    /// When answers are taken from; nil once open.
    public private(set) var opensAt: ContinuousClock.Instant?

    public static let open = AnswerGate(opensAt: nil)

    /// Holds answers until a prompt that starts fading in at `now` has taken `seconds`. A hold that
    /// is already longer stays.
    public func revealing(at now: ContinuousClock.Instant, for seconds: Double) -> AnswerGate {
        combined(with: AnswerGate(opensAt: now + .seconds(seconds)))
    }

    /// Both holds: open once the later one is.
    public func combined(with other: AnswerGate) -> AnswerGate {
        switch (opensAt, other.opensAt) {
        case (nil, _): other
        case (_, nil): self
        case (let mine?, let theirs?): AnswerGate(opensAt: max(mine, theirs))
        }
    }

    public func allowsAnswer(at now: ContinuousClock.Instant) -> Bool {
        opensAt.map { now >= $0 } ?? true
    }
}

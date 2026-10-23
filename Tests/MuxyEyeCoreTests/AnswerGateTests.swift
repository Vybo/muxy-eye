import Testing
@testable import MuxyEyeCore

@Suite struct AnswerGateTests {
    let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant { start + .milliseconds(milliseconds) }

    @Test func anOpenGateTakesAnswersAtOnce() {
        #expect(AnswerGate.open.allowsAnswer(at: start))
    }

    @Test func aPromptFadingInHoldsAnswersUntilItHasFadedIn() {
        let gate = AnswerGate.open.revealing(at: start, for: 0.66)
        #expect(gate.allowsAnswer(at: at(300)) == false)
        #expect(gate.allowsAnswer(at: at(659)) == false)
        #expect(gate.allowsAnswer(at: at(660)))
        #expect(gate.allowsAnswer(at: at(2000)))
    }

    @Test func aLaterRevealHoldsLongerButAnEarlierOneNeverShortensTheHold() {
        let opening = AnswerGate.open.revealing(at: start, for: 0.66)
        #expect(opening.revealing(at: at(600), for: 0.18).allowsAnswer(at: at(700)) == false)
        #expect(opening.revealing(at: at(100), for: 0.15).allowsAnswer(at: at(400)) == false)
    }

    @Test func nestedGatesHoldUntilTheLaterOneOpens() {
        let panel = AnswerGate.open.revealing(at: start, for: 0.66)
        let prompt = AnswerGate.open.revealing(at: at(100), for: 0.15)
        let shown = panel.combined(with: prompt)
        #expect(shown.allowsAnswer(at: at(500)) == false)
        #expect(shown.allowsAnswer(at: at(660)))
        #expect(prompt.combined(with: .open) == prompt)
    }
}

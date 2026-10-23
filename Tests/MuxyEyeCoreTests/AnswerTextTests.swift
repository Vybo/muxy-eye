import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct AnswerTextTests {
    @Test func lineBreaksBecomeSingleSpaces() {
        #expect(AnswerText.sanitized("fix\nthe bug") == "fix the bug")
        #expect(AnswerText.sanitized("a\r\nb") == "a b")
        #expect(AnswerText.sanitized("a\rb") == "a b")
        #expect(AnswerText.sanitized("a\n\n\nb") == "a b")
        #expect(AnswerText.sanitized("a\u{2028}b") == "a b")
    }

    @Test func escapeAndOtherControlCharactersAreRemoved() {
        #expect(AnswerText.sanitized("go\u{1B}[C left") == "go[C left")
        #expect(AnswerText.sanitized("a\u{07}b\u{7F}c\u{00}d\u{9B}e") == "abcde")
    }

    @Test func tabsBecomeSpaces() {
        #expect(AnswerText.sanitized("a\tb") == "a b")
    }

    @Test func endsAreTrimmed() {
        #expect(AnswerText.sanitized("  use trash instead \n") == "use trash instead")
        #expect(AnswerText.sanitized("\u{1B} hi") == "hi")
    }

    @Test func nothingLeftIsNil() {
        #expect(AnswerText.sanitized("") == nil)
        #expect(AnswerText.sanitized("   ") == nil)
        #expect(AnswerText.sanitized("\n\r\n") == nil)
        #expect(AnswerText.sanitized("\u{1B}\u{07}") == nil)
    }

    @Test func ordinaryTextIsUnchanged() {
        #expect(AnswerText.sanitized("Žluťoučký kůň 🐎 -- \"quoted\" $HOME") == "Žluťoučký kůň 🐎 -- \"quoted\" $HOME")
    }

    @Test func answersWithTextAreSanitized() {
        #expect(UserAnswer.reply("next\nstep").sanitized == .reply("next step"))
        #expect(UserAnswer.deny(feedback: " use\u{1B}trash ").sanitized == .deny(feedback: "usetrash"))
        #expect(UserAnswer.freeText("Teal\r\n").sanitized == .freeText("Teal"))
    }

    @Test func emptyTextAnswersAreNil() {
        #expect(UserAnswer.reply("  \n").sanitized == nil)
        #expect(UserAnswer.deny(feedback: "").sanitized == nil)
        #expect(UserAnswer.freeText("\u{1B}").sanitized == nil)
    }

    @Test func answersWithoutTextPassThrough() {
        #expect(UserAnswer.option(2).sanitized == .option(2))
        #expect(UserAnswer.multiSelect([1, 3]).sanitized == .multiSelect([1, 3]))
    }
}

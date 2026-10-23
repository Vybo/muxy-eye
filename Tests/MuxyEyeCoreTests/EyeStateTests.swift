import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct EyeStateTests {
    let color = Question(question: "Which color?", header: "Color", options: [QuestionOption(label: "Red", description: nil)], multiSelect: false)
    let size = Question(question: "Which size?", header: "Size", options: [QuestionOption(label: "Small", description: nil)], multiSelect: false)
    let at = Date(timeIntervalSince1970: 1_000)

    func item(_ kind: PendingKind, at date: Date? = nil, sawBlocked: Bool = false) -> PendingItem {
        PendingItem(kind: kind, receivedAt: date ?? at, sawBlocked: sawBlocked)
    }

    @Test func samePromptIgnoresWhetherMuxySawItBlocked() {
        let shown = item(.question(QuestionRequest(questions: [color, size])))
        #expect(shown.isSamePrompt(as: item(.question(QuestionRequest(questions: [color, size])), sawBlocked: true)))
    }

    @Test func laterArrivalOrOtherContentIsAnotherPrompt() {
        let bash = PendingKind.permission(PermissionRequest(toolName: "Bash", toolInput: .object(["command": .string("ls")])))
        let rm = PendingKind.permission(PermissionRequest(toolName: "Bash", toolInput: .object(["command": .string("rm -rf x")])))
        #expect(!item(bash).isSamePrompt(as: item(bash, at: at.addingTimeInterval(1))))
        #expect(!item(bash).isSamePrompt(as: item(rm)))
        #expect(!item(bash).isSamePrompt(as: item(.finished(message: nil))))
    }

    @Test func narrowingKeepsOnlyTheShownQuestion() throws {
        let full = item(.question(QuestionRequest(questions: [color, size])), sawBlocked: true)
        let narrowed = try #require(full.narrowed(toQuestion: "Which size?"))
        #expect(narrowed.kind == .question(QuestionRequest(questions: [size])))
        #expect(narrowed.receivedAt == full.receivedAt)
        #expect(narrowed.sawBlocked)
    }

    @Test func narrowingToAnUnknownQuestionOrAnotherKindIsNil() {
        #expect(item(.question(QuestionRequest(questions: [color]))).narrowed(toQuestion: "Which shape?") == nil)
        #expect(item(.finished(message: "Done.")).narrowed(toQuestion: "Which color?") == nil)
    }
}

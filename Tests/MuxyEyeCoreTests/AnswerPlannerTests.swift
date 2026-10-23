import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct AnswerPlannerTests {
    func pending(_ name: String) throws -> PendingItem {
        let envelope = try JSONDecoder().decode(HookEnvelope.self, from: Fixture.data("hooks/\(name).json"))
        let event = try #require(HookDecoder.decode(envelope))
        switch event.event {
        case .permission(let r): return PendingItem(kind: .permission(r), receivedAt: .now, sawBlocked: false)
        case .question(let q): return PendingItem(kind: .question(q), receivedAt: .now, sawBlocked: false)
        default: throw Fixture.FixtureError.missing(name)
        }
    }

    func screen(_ name: String) throws -> ScreenPrompt? {
        ScreenParser.parse(try Fixture.text("screens/\(name).txt"))
    }

    @Test func approveBash() throws {
        let s = try screen("permission-bash")
        #expect(AnswerPlanner.steps(for: .option(1), pending: try pending("permission-request-bash"), screen: s, idlePrompt: false) == .success([.text("1")]))
    }

    @Test func denyWithFeedback() throws {
        let s = try screen("permission-bash")
        #expect(AnswerPlanner.steps(for: .deny(feedback: "use trash instead"), pending: try pending("permission-request-bash"), screen: s, idlePrompt: false)
                == .success([.text("4"), .expectIdlePrompt, .text("use trash instead"), .key(.enter)]))
    }

    @Test func wrongScreenIsPromptChanged() throws {
        let other = try screen("permission-bash-rm")
        #expect(AnswerPlanner.steps(for: .option(1), pending: try pending("permission-request-bash"), screen: other, idlePrompt: false) == .failure(.promptChanged))
        #expect(AnswerPlanner.steps(for: .option(1), pending: try pending("permission-request-bash"), screen: nil, idlePrompt: false) == .failure(.promptChanged))
    }

    @Test func writeMatchesByFileName() throws {
        let s = try screen("permission-write")
        #expect(AnswerPlanner.matches(try pending("permission-request-write"), screen: s, idlePrompt: false))
    }

    @Test func questionOptionAndFreeText() throws {
        let s = try screen("question-single")
        let p = try pending("pre-tool-use-question-single")
        #expect(AnswerPlanner.steps(for: .option(2), pending: p, screen: s, idlePrompt: false) == .success([.text("2")]))
        #expect(AnswerPlanner.steps(for: .freeText("Teal"), pending: p, screen: s, idlePrompt: false)
                == .success([.text("4"), .text("Teal"), .key(.enter)]))
        #expect(AnswerPlanner.steps(for: .option(9), pending: p, screen: s, idlePrompt: false) == .failure(.noMatchingOption))
        #expect(AnswerPlanner.steps(for: .multiSelect([1]), pending: p, screen: s, idlePrompt: false) == .failure(.unsupported))
        #expect(AnswerPlanner.steps(for: .reply("x"), pending: p, screen: s, idlePrompt: true) == .failure(.promptChanged))
    }

    @Test func multiSelectTogglesOnlyDifferences() throws {
        let toggled = try screen("question-multi-toggled")
        #expect(AnswerPlanner.steps(for: .multiSelect([2, 3]), pending: try pending("pre-tool-use-question-multi"), screen: toggled, idlePrompt: false)
                == .success([.text("1"), .text("3"), .text("\u{1B}[C"), .expectSubmitReview, .text("1")]))
    }

    @Test func replyNeedsIdlePrompt() {
        let finished = PendingItem(kind: .finished(message: "Done."), receivedAt: .now, sawBlocked: false)
        #expect(AnswerPlanner.steps(for: .reply("next"), pending: finished, screen: nil, idlePrompt: true) == .success([.text("next"), .key(.enter)]))
        #expect(AnswerPlanner.steps(for: .reply("next"), pending: finished, screen: nil, idlePrompt: false) == .failure(.promptChanged))
    }

    @Test func currentQuestionMatchesScreen() throws {
        let s = try screen("question-single")
        guard case .question(let q) = try pending("pre-tool-use-question-single").kind else { Issue.record("not question"); return }
        #expect(q.current(on: s)?.question == "Which color do you prefer?")
        #expect(q.current(on: nil) == nil)
    }

    func screen(_ name: String, replacing target: String, with replacement: String) throws -> ScreenPrompt? {
        let text = try Fixture.text("screens/\(name).txt")
        #expect(text.contains(target))
        return ScreenParser.parse(text.replacingOccurrences(of: target, with: replacement))
    }

    func permissionPending(tool: String, input: [String: JSONValue]) -> PendingItem {
        PendingItem(kind: .permission(PermissionRequest(toolName: tool, toolInput: .object(input))), receivedAt: .now, sawBlocked: false)
    }

    @Test func stalePrefixCommandDoesNotMatch() throws {
        let s = try screen("permission-bash", replacing: " touch spike-ok.txt\n", with: " touch spike-ok.txt --force\n")
        #expect(AnswerPlanner.steps(for: .option(1), pending: try pending("permission-request-bash"), screen: s, idlePrompt: false) == .failure(.promptChanged))
    }

    @Test func shortCommandDoesNotMatchDescription() throws {
        let p = permissionPending(tool: "Bash", input: ["command": .string("file")])
        #expect(!AnswerPlanner.matches(p, screen: try screen("permission-bash"), idlePrompt: false))
    }

    @Test func wrappedCommandMatches() throws {
        let s = try screen("permission-bash", replacing: " touch spike-ok.txt\n", with: " touch\n spike-ok.txt\n")
        #expect(AnswerPlanner.matches(try pending("permission-request-bash"), screen: s, idlePrompt: false))
    }

    @Test func nilPrimaryTextFailsClosed() throws {
        let p = permissionPending(tool: "mcp__x__y", input: [:])
        #expect(!AnswerPlanner.matches(p, screen: try screen("permission-bash"), idlePrompt: false))
    }

    @Test func fileNameBoundary() throws {
        let s = try screen("permission-write")
        let data = permissionPending(tool: "Write", input: ["file_path": .string("/p/data.txt")])
        #expect(!AnswerPlanner.matches(data, screen: try screen("permission-write", replacing: "\n notes.md\n", with: "\n a.txt\n"), idlePrompt: false))
        let notes = permissionPending(tool: "Write", input: ["file_path": .string("/p/notes.md")])
        #expect(AnswerPlanner.matches(notes, screen: s, idlePrompt: false))
        let other = permissionPending(tool: "Write", input: ["file_path": .string("/p/xnotes.md")])
        #expect(!AnswerPlanner.matches(other, screen: s, idlePrompt: false))
    }

    @Test func questionTextMismatchIsPromptChanged() throws {
        let s = try screen("question-single")
        #expect(AnswerPlanner.steps(for: .option(1), pending: try pending("pre-tool-use-question-multi"), screen: s, idlePrompt: false) == .failure(.promptChanged))
    }

    @Test func questionLabelMismatchIsPromptChanged() throws {
        let s = try screen("question-single", replacing: "1. Red", with: "1. Crimson")
        #expect(AnswerPlanner.steps(for: .option(1), pending: try pending("pre-tool-use-question-single"), screen: s, idlePrompt: false) == .failure(.promptChanged))
    }

    @Test func denyOnQuestionIsUnsupported() throws {
        let s = try screen("question-single")
        #expect(AnswerPlanner.steps(for: .deny(feedback: "x"), pending: try pending("pre-tool-use-question-single"), screen: s, idlePrompt: false) == .failure(.unsupported))
    }

    @Test func freeTextOnPermissionIsUnsupported() throws {
        let s = try screen("permission-bash")
        #expect(AnswerPlanner.steps(for: .freeText("x"), pending: try pending("permission-request-bash"), screen: s, idlePrompt: false) == .failure(.unsupported))
    }

    @Test func optionOnMultiSelectIsUnsupported() throws {
        let s = try screen("question-multi-toggled")
        #expect(AnswerPlanner.steps(for: .option(1), pending: try pending("pre-tool-use-question-multi"), screen: s, idlePrompt: false) == .failure(.unsupported))
    }

    @Test func multiSelectOutOfRangeIsNoMatchingOption() throws {
        let s = try screen("question-multi-toggled")
        #expect(AnswerPlanner.steps(for: .multiSelect([5]), pending: try pending("pre-tool-use-question-multi"), screen: s, idlePrompt: false) == .failure(.noMatchingOption))
    }

    @Test func freeTextOptionComesFromTheScreen() throws {
        #expect(AnswerPlanner.freeTextOption(on: try screen("question-single"))?.number == 4)
        #expect(AnswerPlanner.freeTextOption(on: try screen("question-single-type-something"))?.number == 4)
        #expect(AnswerPlanner.freeTextOption(on: try screen("question-multi"))?.number == 4)
        #expect(AnswerPlanner.freeTextOption(on: try screen("permission-bash")) == nil)
        #expect(AnswerPlanner.freeTextOption(on: nil) == nil)
    }

    @Test func denyOptionComesFromTheScreen() throws {
        #expect(AnswerPlanner.denyOption(on: try screen("permission-bash"))?.number == 4)
        #expect(AnswerPlanner.denyOption(on: try screen("permission-write"))?.number == 3)
        #expect(AnswerPlanner.denyOption(on: try screen("permission-bash", replacing: "4. No", with: "4. No, and tell Claude what to do differently"))?.number == 4)
        #expect(AnswerPlanner.denyOption(on: try screen("permission-bash", replacing: "4. No", with: "4. Nope")) == nil)
        #expect(AnswerPlanner.denyOption(on: try screen("question-single")) == nil)
        #expect(AnswerPlanner.denyOption(on: nil) == nil)
    }

    @Test func denyWithoutNoOptionIsNoMatchingOption() throws {
        let s = try screen("permission-bash", replacing: "4. No", with: "4. Maybe")
        #expect(AnswerPlanner.steps(for: .deny(feedback: "x"), pending: try pending("permission-request-bash"), screen: s, idlePrompt: false) == .failure(.noMatchingOption))
    }
}

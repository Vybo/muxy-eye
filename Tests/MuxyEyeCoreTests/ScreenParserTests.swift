import Testing
@testable import MuxyEyeCore

@Suite struct ScreenParserTests {
    func screen(_ name: String) throws -> String { try Fixture.text("screens/\(name).txt") }

    @Test func parsesBashPermission() throws {
        guard case .permission(let title, let body, let question, let options) = ScreenParser.parse(try screen("permission-bash")) else { Issue.record("no prompt"); return }
        #expect(title == "Bash command")
        #expect(body.contains("touch spike-ok.txt"))
        #expect(question == "Do you want to proceed?")
        #expect(options.map(\.number) == [1, 2, 3, 4])
        #expect(options[0] == ScreenOption(number: 1, label: "Yes", description: nil, isCursor: true, checked: nil))
        #expect(options[1].label == "Yes, and always allow access to /private/tmp/muxy-eye-spikes/claude-code-2.1.309/permission-and-question-prompts/sample-web-project/spike from this project")
        #expect(options[2].label == "Yes, and switch to auto mode · auto mode handles these prompts for you")
        #expect(options[3].label == "No")
    }
    @Test func parsesWritePermissionWithWordWrappedOption() throws {
        guard case .permission(let title, _, let question, let options) = ScreenParser.parse(try screen("permission-write")) else { Issue.record(""); return }
        #expect(title == "Create file")
        #expect(question == "Do you want to create notes.md?")
        #expect(options.count == 3)
        #expect(options[1].label == "Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)")
    }
    @Test func parsesSingleQuestion() throws {
        guard case .question(let header, let question, let options, let multi) = ScreenParser.parse(try screen("question-single")) else { Issue.record(""); return }
        #expect(header == "Color")
        #expect(question == "Which color do you prefer?")
        #expect(multi == false)
        #expect(options.map(\.label) == ["Red", "Green", "Blue", "Type something.", "Chat about this"])
        #expect(options[0].description == "Warm, bold color")
        #expect(options[0].isCursor)
    }
    @Test func cursorMovesToTypeSomething() throws {
        guard case .question(_, _, let options, _) = ScreenParser.parse(try screen("question-single-type-something")) else { Issue.record(""); return }
        #expect(options.first(where: \.isCursor)?.number == 4)
    }
    @Test func parsesMultiSelect() throws {
        guard case .question(let header, _, let options, let multi) = ScreenParser.parse(try screen("question-multi")) else { Issue.record(""); return }
        #expect(header == "Platforms")
        #expect(multi)
        #expect(options.prefix(4).map(\.checked) == [false, false, false, false])
        guard case .question(_, _, let toggled, _) = ScreenParser.parse(try screen("question-multi-toggled")) else { Issue.record(""); return }
        #expect(toggled.prefix(3).map(\.checked) == [true, true, false])
    }
    @Test func parsesSubmitReview() throws {
        #expect(ScreenParser.parse(try screen("question-submit-review")) == .submitReview(options: [
            ScreenOption(number: 1, label: "Submit answers", description: nil, isCursor: true, checked: nil),
            ScreenOption(number: 2, label: "Cancel", description: nil, isCursor: false, checked: nil)]))
    }
    @Test func nonPromptsParseToNil() throws {
        #expect(ScreenParser.parse(try screen("trust-dialog")) == nil)
        #expect(ScreenParser.parse(try screen("idle-after-deny")) == nil)
        #expect(ScreenParser.isAtIdlePrompt(try screen("idle-after-deny")))
        #expect(ScreenParser.isAtIdlePrompt(try screen("permission-bash")) == false)
    }
    @Test func numberedListInAssistantMessageIsNotAPrompt() throws {
        let s = try screen("idle-after-deny").replacingOccurrences(of: "✻ Cogitated", with: "⏺ Options:\n  1. First thing\n  2. Second thing\n✻ Cogitated")
        #expect(ScreenParser.parse(s) == nil)
        #expect(ScreenParser.isAtIdlePrompt(s))
    }
    @Test func realPromptBelowNumberedListWins() throws {
        let s = try screen("permission-bash").replacingOccurrences(of: "⏺ Bash(touch", with: "  1. earlier list item\n  2. another\n⏺ Bash(touch")
        guard case .permission(_, _, _, let options) = ScreenParser.parse(s) else { Issue.record(""); return }
        #expect(options.first?.label == "Yes")
    }
}

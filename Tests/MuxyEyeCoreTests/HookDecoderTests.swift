import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct HookDecoderTests {
    func envelope(_ name: String) throws -> HookEnvelope {
        try JSONDecoder().decode(HookEnvelope.self, from: Fixture.data("hooks/\(name).json"))
    }

    @Test func decodesBashPermission() throws {
        let event = try #require(HookDecoder.decode(envelope("permission-request-bash")))
        #expect(event.muxySession == MuxySessionID("5602690846448319352"))
        #expect(event.claudeSessionID == "b66388e5-d65c-41e2-b38d-920e1aa443b8")
        guard case .permission(let request) = event.event else { Issue.record("not permission"); return }
        #expect(request.title == "Bash command")
        #expect(request.primaryText == "touch spike-ok.txt")
        #expect(request.detail == "Create empty file spike-ok.txt")
    }

    @Test func decodesWritePermissionTitle() throws {
        guard case .permission(let r) = try #require(HookDecoder.decode(envelope("permission-request-write"))).event else { Issue.record("not permission"); return }
        #expect(r.title == "Create file")
        #expect(r.primaryText?.hasSuffix("/notes.md") == true)
    }

    @Test func askUserQuestionPermissionIsIgnored() throws {
        #expect(HookDecoder.decode(try envelope("permission-request-ask-user-question")) == nil)
    }

    @Test func decodesQuestions() throws {
        guard case .question(let single) = try #require(HookDecoder.decode(envelope("pre-tool-use-question-single"))).event else { Issue.record("not question"); return }
        #expect(single.questions.first?.question == "Which color do you prefer?")
        #expect(single.questions.first?.options.map(\.label) == ["Red", "Green", "Blue"])
        #expect(single.questions.first?.multiSelect == false)
        guard case .question(let multi) = try #require(HookDecoder.decode(envelope("pre-tool-use-question-multi"))).event else { Issue.record("not question"); return }
        #expect(multi.questions.first?.multiSelect == true)
    }

    @Test func decodesLifecycleEvents() throws {
        #expect(HookDecoder.decode(try envelope("stop"))?.event == .stop(lastAssistantMessage: "Done. `spike-ok.txt` created."))
        #expect(HookDecoder.decode(try envelope("user-prompt-submit"))?.event == .userPromptSubmit)
        #expect(HookDecoder.decode(try envelope("post-tool-use-bash"))?.event == .postToolUse(toolName: "Bash"))
        #expect(HookDecoder.decode(try envelope("session-end"))?.event == .sessionEnd)
        #expect(HookDecoder.decode(try envelope("notification-permission-prompt"))?.event == .notification(type: "permission_prompt", message: "Claude needs your permission"))
        guard case .sessionStart = try #require(HookDecoder.decode(envelope("session-start"))).event else { Issue.record("not sessionStart"); return }
    }

    @Test func unknownEventDecodesToNil() throws {
        var e = try envelope("stop"); e.event = "SomethingNew"
        #expect(HookDecoder.decode(e) == nil)
    }

    @Test func wirePaths() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(HookWire.defaultSocketURL(home: home).path == "/Users/x/Library/Application Support/Muxy Eye/eye.sock")
        #expect(HookWire.installedHelperURL(home: home).path == "/Users/x/Library/Application Support/Muxy Eye/bin/muxy-eye-hook")
    }
}

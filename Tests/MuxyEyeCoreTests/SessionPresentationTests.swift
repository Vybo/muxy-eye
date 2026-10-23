import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct SessionPresentationTests {
    let now = Date(timeIntervalSince1970: 10_000)
    let state = EyeState()

    func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    func record(
        provider: String = "Claude",
        state muxyState: AgentState = .idle,
        pending: PendingKind? = nil,
        receivedSecondsAgo: TimeInterval = 0,
        blockedSecondsAgo: TimeInterval? = nil,
        unreadCompleted: Bool = false
    ) -> SessionRecord {
        SessionRecord(
            id: MuxySessionID("S"),
            provider: provider,
            projectID: "p",
            projectName: "muxy-eye",
            muxyState: muxyState,
            blockedSince: blockedSecondsAgo.map(ago),
            pending: pending.map { PendingItem(kind: $0, receivedAt: ago(receivedSecondsAgo), sawBlocked: false) },
            unreadCompletedEventID: unreadCompleted ? "e1" : nil,
            unreadCompletedAt: unreadCompleted ? ago(30) : nil
        )
    }

    let bash = PermissionRequest(toolName: "Bash", toolInput: .object(["command": .string("ls")]))

    func question(_ text: String, header: String) -> Question {
        Question(question: text, header: header, options: [QuestionOption(label: "A", description: nil)], multiSelect: false)
    }

    func subtitle(_ r: SessionRecord) -> String {
        SessionPresentation.railSubtitle(for: r, in: state, now: now)
    }

    @Test func ageUsesTheLargestWholeUnit() {
        #expect(SessionPresentation.age(0) == "0s")
        #expect(SessionPresentation.age(40.9) == "40s")
        #expect(SessionPresentation.age(59) == "59s")
        #expect(SessionPresentation.age(60) == "1m")
        #expect(SessionPresentation.age(150) == "2m")
        #expect(SessionPresentation.age(3_599) == "59m")
        #expect(SessionPresentation.age(3_600) == "1h")
        #expect(SessionPresentation.age(86_400 * 2 + 5) == "2d")
        #expect(SessionPresentation.age(-5) == "0s")
    }

    @Test func claudeSubtitlesShowKindAndAge() {
        #expect(subtitle(record(state: .blocked, pending: .permission(bash), receivedSecondsAgo: 120)) == "approval · 2m")
        #expect(subtitle(record(state: .blocked, pending: .question(QuestionRequest(questions: [])), receivedSecondsAgo: 40)) == "question · 40s")
        #expect(subtitle(record(pending: .finished(message: "Done."), receivedSecondsAgo: 10)) == "finished · 10s")
        #expect(subtitle(record(state: .blocked, blockedSecondsAgo: 5)) == "needs input · 5s")
    }

    @Test func claudeSubtitlesWithoutAPromptShowTheState() {
        #expect(subtitle(record(state: .working)) == "working")
        #expect(subtitle(record(state: .idle)) == "idle")
        #expect(subtitle(record(state: .unknown)) == "idle")
    }

    @Test func otherProvidersShowProviderAndState() {
        #expect(subtitle(record(provider: "Codex", state: .working)) == "Codex · working")
        #expect(subtitle(record(provider: "Codex", state: .blocked, blockedSecondsAgo: 70)) == "Codex · needs input")
        #expect(subtitle(record(provider: "Codex", state: .idle, unreadCompleted: true)) == "Codex · finished")
        #expect(subtitle(record(provider: "Codex", state: .idle)) == "Codex · idle")
    }

    @Test func kindLabels() {
        func label(_ r: SessionRecord, _ screen: ScreenPrompt? = nil) -> String? {
            SessionPresentation.kindLabel(for: r, in: state, screen: screen)
        }
        #expect(label(record(state: .blocked, pending: .permission(bash))) == "BASH COMMAND")
        let write = PermissionRequest(toolName: "Write", toolInput: .object(["file_path": .string("/p/a.md")]))
        #expect(label(record(state: .blocked, pending: .permission(write))) == "CREATE FILE")
        #expect(label(record(state: .blocked, pending: .question(QuestionRequest(questions: [question("Q?", header: "Color")])))) == "QUESTION · COLOR")
        #expect(label(record(state: .blocked, pending: .question(QuestionRequest(questions: [question("Q?", header: "")])))) == "QUESTION")
        #expect(label(record(state: .blocked, pending: .question(QuestionRequest(questions: [])))) == "QUESTION")
        #expect(label(record(pending: .finished(message: nil))) == "FINISHED")
        #expect(label(record(state: .blocked, blockedSecondsAgo: 1)) == "NEEDS INPUT")
        #expect(label(record(provider: "Codex", state: .blocked, blockedSecondsAgo: 1)) == "NEEDS INPUT")
        #expect(label(record(provider: "Codex", state: .idle, unreadCompleted: true)) == "FINISHED")
        #expect(label(record(state: .working)) == nil)
        #expect(label(record(state: .idle)) == nil)
    }

    @Test func questionKindLabelFollowsTheQuestionOnScreen() throws {
        let request = QuestionRequest(questions: [
            question("Which platforms?", header: "Platforms"),
            question("Which color do you prefer?", header: "Color")
        ])
        let r = record(state: .blocked, pending: .question(request))
        let screen = ScreenParser.parse(try Fixture.text("screens/question-single.txt"))
        #expect(SessionPresentation.kindLabel(for: r, in: state, screen: screen) == "QUESTION · COLOR")
        #expect(SessionPresentation.kindLabel(for: r, in: state, screen: nil) == "QUESTION · PLATFORMS")
    }

    @Test func screenTailKeepsTheLastNonEmptyLines() {
        let screen = "a\n\n  b  \n   \nc\n\n\n"
        #expect(SessionPresentation.screenTail(screen, lines: 2) == ["  b", "c"])
        #expect(SessionPresentation.screenTail(screen) == ["a", "  b", "c"])
        #expect(SessionPresentation.screenTail("") == [])
        #expect(SessionPresentation.screenTail("x\r\ny\r\n") == ["x", "y"])
    }

    @Test func screenTailOfARealScreenHasFifteenLines() throws {
        let tail = SessionPresentation.screenTail(try Fixture.text("screens/permission-bash.txt"))
        #expect(tail.count == 15)
        #expect(tail.last == " Esc to cancel · Tab to amend")
        #expect(tail.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.last != " " })
    }

    @Test func displayNameFallsBackToDirectoryThenProvider() {
        var r = record()
        #expect(SessionPresentation.displayName(for: r) == "muxy-eye")
        r.projectName = ""
        r.directory = "/Users/me/code/atlas/"
        #expect(SessionPresentation.displayName(for: r) == "atlas")
        r.directory = nil
        #expect(SessionPresentation.displayName(for: r) == "Claude")
    }

    @Test func headerDetailJoinsWorktreeAndProvider() {
        var r = record()
        #expect(SessionPresentation.headerDetail(for: r) == "Claude")
        r.subtitle = "feature-rail"
        #expect(SessionPresentation.headerDetail(for: r) == "feature-rail · Claude")
        r.subtitle = ""
        #expect(SessionPresentation.headerDetail(for: r) == "Claude")
    }
}

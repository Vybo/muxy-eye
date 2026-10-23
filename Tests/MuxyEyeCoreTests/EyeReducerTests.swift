import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct EyeReducerTests {
    let a = MuxySessionID("A")
    let b = MuxySessionID("B")
    let c = MuxySessionID("C")
    let d = MuxySessionID("D")

    func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func agent(_ id: String, _ state: AgentState, provider: String = "Claude") -> AgentActivity {
        AgentActivity(session: MuxySessionID(id), project: "p", provider: provider, state: state)
    }

    func snap(_ agents: [AgentActivity], events: [ActivityEvent] = []) -> ActivitySnapshot {
        ActivitySnapshot(revision: 1, agents: agents, events: events)
    }

    func event(_ id: String, _ session: String, _ kind: ActivityEventKind, read: Bool, ts: Int64 = 100, provider: String = "Claude") -> ActivityEvent {
        ActivityEvent(id: id, session: MuxySessionID(session), project: "p", provider: provider, timestamp: ts, kind: kind, read: read)
    }

    func hook(_ id: String, _ e: ClaudeHookEvent) -> HookEvent {
        HookEvent(muxySession: MuxySessionID(id), claudeSessionID: nil, event: e)
    }

    let permission = PermissionRequest(toolName: "Bash", toolInput: .object(["command": .string("ls")]))

    @discardableResult
    func run(_ state: inout EyeState, _ action: EyeAction) -> [EyeEffect] {
        EyeReducer.reduce(&state, action)
    }

    @Test func snapshotCreatesAndRemovesRecords() {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working), agent("B", .idle)]), at: t(0)))
        #expect(s.sessions.count == 2)
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(1)))
        #expect(s.sessions.count == 1)
        #expect(s.sessions[b] == nil)
    }

    @Test func newSessionEmitsRefreshMetadata() {
        var s = EyeState()
        let first = run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        #expect(first.contains(.refreshMetadata))
        let second = run(&s, .snapshot(snap([agent("A", .working)]), at: t(1)))
        #expect(!second.contains(.refreshMetadata))
    }

    @Test func permissionHookCreatesPending() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        let effects = run(&s, .hook(hook("A", .permission(permission)), at: t(1)))
        #expect(try #require(s.sessions[a]).pending?.kind == .permission(permission))
        #expect(effects == [.becameWaiting(a)])
        #expect(s.mode == .waiting)
    }

    @Test func blockedThenWorkingClearsPending() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        run(&s, .hook(hook("A", .permission(permission)), at: t(0)))
        run(&s, .snapshot(snap([agent("A", .blocked)]), at: t(1)))
        #expect(try #require(s.sessions[a]).pending?.sawBlocked == true)
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(2)))
        #expect(try #require(s.sessions[a]).pending == nil)
        #expect(s.mode == .working)
    }

    @Test func neverBlockedPendingExpires() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        run(&s, .hook(hook("A", .permission(permission)), at: t(0)))
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(5)))
        #expect(try #require(s.sessions[a]).pending != nil)
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(11)))
        #expect(try #require(s.sessions[a]).pending == nil)
    }

    @Test func postToolUseClearsPrompt() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        run(&s, .hook(hook("A", .permission(permission)), at: t(1)))
        run(&s, .hook(hook("A", .postToolUse(toolName: "Bash")), at: t(2)))
        #expect(try #require(s.sessions[a]).pending == nil)
    }

    @Test func stopCreatesFinished() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .idle)]), at: t(0)))
        let effects = run(&s, .hook(hook("A", .stop(lastAssistantMessage: "Done.")), at: t(1)))
        let record = try #require(s.sessions[a])
        #expect(record.pending?.kind == .finished(message: "Done."))
        #expect(record.lastAssistantMessage == "Done.")
        #expect(effects == [.becameWaiting(a)])
    }

    @Test func userPromptSubmitClearsFinished() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .idle)]), at: t(0)))
        run(&s, .hook(hook("A", .stop(lastAssistantMessage: "Done.")), at: t(1)))
        run(&s, .hook(hook("A", .userPromptSubmit), at: t(2)))
        #expect(try #require(s.sessions[a]).pending == nil)
    }

    @Test func readCompletedEventClearsFinished() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .idle)]), at: t(0)))
        run(&s, .hook(hook("A", .stop(lastAssistantMessage: "Done.")), at: t(1)))
        run(&s, .snapshot(snap([agent("A", .idle)], events: [event("e1", "A", .completed, read: false)]), at: t(2)))
        let mid = try #require(s.sessions[a])
        #expect(mid.pending != nil)
        #expect(mid.unreadCompletedEventID == "e1")
        run(&s, .snapshot(snap([agent("A", .idle)], events: [event("e1", "A", .completed, read: true)]), at: t(3)))
        #expect(try #require(s.sessions[a]).pending == nil)
    }

    @Test func blockedCodexIsWaitingWithoutPending() throws {
        var s = EyeState()
        let first = run(&s, .snapshot(snap([agent("C", .blocked, provider: "Codex")]), at: t(0)))
        #expect(s.isWaiting(try #require(s.sessions[c])))
        #expect(first.contains(.becameWaiting(c)))
        let second = run(&s, .snapshot(snap([agent("C", .blocked, provider: "Codex")]), at: t(1)))
        #expect(!second.contains(.becameWaiting(c)))
    }

    @Test func nonClaudeUnreadCompletedIsWaiting() throws {
        var s = EyeState()
        let events = [event("e9", "C", .completed, read: false, provider: "Codex")]
        run(&s, .snapshot(snap([agent("C", .idle, provider: "Codex")], events: events), at: t(0)))
        #expect(s.isWaiting(try #require(s.sessions[c])))
        let effects = run(&s, .dismiss(c, at: t(1)))
        #expect(effects == [.ack(eventIDs: ["e9"])])
        #expect(!s.isWaiting(try #require(s.sessions[c])))
    }

    @Test func dismissFinishedAcks() throws {
        var s = EyeState()
        let events = [event("e1", "A", .completed, read: false)]
        run(&s, .snapshot(snap([agent("A", .idle)], events: events), at: t(0)))
        run(&s, .hook(hook("A", .stop(lastAssistantMessage: "Done.")), at: t(0)))
        let effects = run(&s, .dismiss(a, at: t(1)))
        #expect(try #require(s.sessions[a]).pending == nil)
        #expect(effects == [.ack(eventIDs: ["e1"])])
    }

    @Test func answeredAcksUnreadEvents() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        run(&s, .hook(hook("A", .permission(permission)), at: t(0)))
        run(&s, .snapshot(snap([agent("A", .working)], events: [event("e5", "A", .attention, read: false)]), at: t(1)))
        let effects = run(&s, .answered(a, at: t(1)))
        #expect(try #require(s.sessions[a]).pending == nil)
        #expect(effects == [.ack(eventIDs: ["e5"])])
    }

    @Test func hookForUnknownSessionIsProvisional() {
        var s = EyeState()
        run(&s, .hook(hook("X", .permission(permission)), at: t(0)))
        let x = MuxySessionID("X")
        #expect(s.sessions[x] != nil)
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(3)))
        #expect(s.sessions[x] != nil)
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(6)))
        #expect(s.sessions[x] == nil)
    }

    @Test func latestPermissionReplacesPending() throws {
        var s = EyeState()
        let second = PermissionRequest(toolName: "Write", toolInput: .null)
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        let e1 = run(&s, .hook(hook("A", .permission(permission)), at: t(1)))
        let e2 = run(&s, .hook(hook("A", .permission(second)), at: t(2)))
        #expect(try #require(s.sessions[a]).pending?.kind == .permission(second))
        #expect((e1 + e2).filter { $0 == .becameWaiting(a) }.count == 2)
    }

    @Test func sessionEndClearsClaudeState() throws {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        run(&s, .hook(hook("A", .sessionStart(claudeSessionID: "c1")), at: t(1)))
        #expect(try #require(s.sessions[a]).claudeSessionID == "c1")
        run(&s, .hook(hook("A", .permission(permission)), at: t(2)))
        run(&s, .hook(hook("A", .sessionEnd), at: t(3)))
        let record = try #require(s.sessions[a])
        #expect(record.claudeSessionID == nil)
        #expect(record.pending == nil)
    }

    @Test func muxyStoppedResets() {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .working)]), at: t(0)))
        run(&s, .muxyStopped)
        #expect(s.sessions.isEmpty)
        #expect(!s.muxyRunning)
        #expect(s.mode == .idle)
    }

    @Test func railOrdering() {
        var s = EyeState()
        run(&s, .snapshot(snap([agent("A", .idle), agent("B", .idle), agent("C", .working), agent("D", .idle)]), at: t(0)))
        run(&s, .hook(hook("B", .permission(permission)), at: t(2)))
        run(&s, .hook(hook("A", .permission(permission)), at: t(1)))
        #expect(s.rail.map(\.id) == [a, b, c, d])
        #expect(s.waitingCount == 2)
    }

    @Test func worktreeNaming() throws {
        let projects = try JSONDecoder().decode([MuxyProject].self, from: Fixture.data("muxy/project-list.json"))
        let sessions = try JSONDecoder().decode([MuxySessionInfo].self, from: Fixture.data("muxy/session-list.json"))
        var s = EyeState()
        let worktreeSession = MuxySessionID("12684659581346229634")
        let plainSession = MuxySessionID("5602690846448319352")
        run(&s, .snapshot(snap([
            AgentActivity(session: worktreeSession, project: "0dc8bfe9bcd04e0e99a3fd60b0b8eb7b", provider: "Claude", state: .working),
            AgentActivity(session: plainSession, project: "7a51b05fcefd4051aef266dd91d24e48", provider: "Claude", state: .idle)
        ]), at: t(0)))
        run(&s, .metadata(sessions: sessions, projects: projects))
        let worktree = try #require(s.sessions[worktreeSession])
        #expect(worktree.projectName == "acme-ios")
        #expect(worktree.subtitle == "feature/sample-branch")
        let plain = try #require(s.sessions[plainSession])
        #expect(plain.projectName == "muxy-eye")
        #expect(plain.subtitle == nil)
    }
}

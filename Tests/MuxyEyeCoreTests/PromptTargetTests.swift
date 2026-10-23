import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct PromptTargetTests {
    let at = Date(timeIntervalSince1970: 1_000)
    let bash = PendingKind.permission(PermissionRequest(toolName: "Bash", toolInput: .object(["command": .string("ls")])))

    func item(_ kind: PendingKind, at offset: TimeInterval = 0, sawBlocked: Bool = false) -> PendingItem {
        PendingItem(kind: kind, receivedAt: at.addingTimeInterval(offset), sawBlocked: sawBlocked)
    }

    func session(_ id: String, name: String, pending: PendingItem? = nil, state: AgentState = .idle) -> SessionRecord {
        SessionRecord(id: MuxySessionID(id), provider: "Claude", projectID: id, projectName: name, muxyState: state, pending: pending)
    }

    /// "b" waits first, "a" waits later, "c" is idle: the rail is b, a, c.
    var state: EyeState {
        let records = [
            session("a", name: "alpha", pending: item(bash, at: 5)),
            session("b", name: "beta", pending: item(.finished(message: nil))),
            session("c", name: "gamma")
        ]
        return EyeState(sessions: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }))
    }

    @Test func targetsTheSelectedSessionAndThePromptItShows() throws {
        let target = try #require(PromptTarget.displayed(in: state, selected: MuxySessionID("a")))
        #expect(target.session == MuxySessionID("a"))
        #expect(target.pending == item(bash, at: 5))
    }

    @Test func withoutASelectionItTargetsTheRailsFirstSessionAsThePanelShows() throws {
        #expect(state.displayedRecord(selected: nil)?.id == MuxySessionID("b"))
        #expect(PromptTarget.displayed(in: state, selected: nil)?.session == MuxySessionID("b"))
        // A selection that has gone falls back the same way.
        #expect(PromptTarget.displayed(in: state, selected: MuxySessionID("gone"))?.session == MuxySessionID("b"))
    }

    @Test func noSessionsNoTarget() {
        #expect(PromptTarget.displayed(in: EyeState(), selected: MuxySessionID("a")) == nil)
    }

    @Test func aViewOfTheSamePromptActsEvenIfMuxyHasSinceSeenItBlocked() {
        let target = PromptTarget(session: MuxySessionID("a"), pending: item(bash, at: 5))
        #expect(target.matches(session: MuxySessionID("a"), pending: item(bash, at: 5, sawBlocked: true)))
    }

    @Test func aViewOfAnotherSessionIgnoresTheKey() {
        let target = PromptTarget(session: MuxySessionID("b"), pending: item(bash, at: 5))
        #expect(target.matches(session: MuxySessionID("a"), pending: item(bash, at: 5)) == false)
    }

    @Test func aViewOfAReplacedPromptIgnoresTheKey() {
        let target = PromptTarget(session: MuxySessionID("a"), pending: item(bash, at: 9))
        #expect(target.matches(session: MuxySessionID("a"), pending: item(bash, at: 5)) == false)
        #expect(target.matches(session: MuxySessionID("a"), pending: item(.finished(message: nil), at: 9)) == false)
    }

    @Test func aKeyPressedWhileNoPromptShowsMatchesNothing() {
        let target = PromptTarget(session: MuxySessionID("c"), pending: nil)
        #expect(target.matches(session: MuxySessionID("c"), pending: item(bash)) == false)
    }
}

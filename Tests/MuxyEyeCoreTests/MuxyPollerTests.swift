import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct MuxyPollerTests {
    private let snapshot = ActivitySnapshot(revision: 1, agents: [], events: [])
    private let at = Date(timeIntervalSince1970: 1_000)

    private func poller(_ muxy: FakeMuxy) -> MuxyPoller {
        MuxyPoller(muxy: muxy, now: { [at] in at })
    }

    @Test func stoppedServerRunsOnlyStatus() async {
        let muxy = FakeMuxy()
        await muxy.setStatus(.stopped)
        let actions = await poller(muxy).poll(includeMetadata: true)
        #expect(actions.count == 1)
        guard case .muxyStopped = actions[0] else {
            Issue.record("expected muxyStopped")
            return
        }
        #expect(await muxy.calls == ["serverStatus"])
    }

    @Test func runningServerSnapshotsAndOptionalMetadata() async {
        let muxy = FakeMuxy()
        await muxy.setActivity([snapshot])

        let plain = await poller(muxy).poll(includeMetadata: false)
        #expect(plain.count == 1)
        if case let .snapshot(s, date) = plain[0] {
            #expect(s == snapshot)
            #expect(date == at)
        } else {
            Issue.record("expected snapshot")
        }
        #expect(await muxy.calls == ["serverStatus", "activity"])

        let full = await poller(muxy).poll(includeMetadata: true)
        #expect(full.count == 2)
        guard case .snapshot = full[0], case .metadata = full[1] else {
            Issue.record("expected snapshot then metadata")
            return
        }
        #expect(await muxy.calls == ["serverStatus", "activity", "serverStatus", "activity", "sessions", "projects"])
    }

    @Test func activityErrorYieldsNoActions() async {
        let muxy = FakeMuxy()
        let actions = await poller(muxy).poll(includeMetadata: true)
        #expect(actions.isEmpty)
        #expect(await muxy.calls == ["serverStatus", "activity"])
    }

    @Test func intervals() {
        func record(_ id: String, state: AgentState = .idle, pending: PendingItem? = nil) -> SessionRecord {
            SessionRecord(id: MuxySessionID(id), provider: "Claude", projectID: "p", muxyState: state, pending: pending)
        }
        func state(_ records: [SessionRecord]) -> EyeState {
            EyeState(sessions: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }), muxyRunning: true)
        }
        let item = PendingItem(kind: .finished(message: nil), receivedAt: at, sawBlocked: false)

        #expect(PollPolicy.interval(for: EyeState()) == .seconds(3))
        #expect(PollPolicy.interval(for: state([record("a")])) == .seconds(3))
        #expect(PollPolicy.interval(for: state([record("a"), record("b", state: .working)])) == .seconds(1))
        #expect(PollPolicy.interval(for: state([record("a", state: .blocked)])) == .seconds(1))
        #expect(PollPolicy.interval(for: state([record("a", pending: item)])) == .seconds(1))
    }

    @Test func autoExpandRules() {
        let waiting: [EyeEffect] = [.becameWaiting(MuxySessionID("a"))]
        #expect(AutoExpandPolicy.shouldExpand(effects: waiting, enabled: true, muxyFrontmost: false, panelExpanded: false))
        #expect(!AutoExpandPolicy.shouldExpand(effects: waiting, enabled: false, muxyFrontmost: false, panelExpanded: false))
        #expect(!AutoExpandPolicy.shouldExpand(effects: waiting, enabled: true, muxyFrontmost: true, panelExpanded: false))
        #expect(!AutoExpandPolicy.shouldExpand(effects: waiting, enabled: true, muxyFrontmost: false, panelExpanded: true))
        #expect(!AutoExpandPolicy.shouldExpand(effects: [.ack(eventIDs: ["e"])], enabled: true, muxyFrontmost: false, panelExpanded: false))
        #expect(!AutoExpandPolicy.shouldExpand(effects: [], enabled: true, muxyFrontmost: false, panelExpanded: false))
    }

    @Test func muxyBundleIdentifiers() {
        #expect(MuxyApp.bundleIdentifiers == ["com.muxy.app", "com.muxy-beta.app"])
    }
}

import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct AnswerExecutorTests {
    let session = MuxySessionID("s1")

    func pending(_ name: String) throws -> PendingItem {
        let envelope = try JSONDecoder().decode(HookEnvelope.self, from: Fixture.data("hooks/\(name).json"))
        let event = try #require(HookDecoder.decode(envelope))
        switch event.event {
        case .permission(let r): return PendingItem(kind: .permission(r), receivedAt: .now, sawBlocked: false)
        case .question(let q): return PendingItem(kind: .question(q), receivedAt: .now, sawBlocked: false)
        default: throw Fixture.FixtureError.missing(name)
        }
    }

    func snapshot(_ state: AgentState?) -> ActivitySnapshot {
        let agents = state.map { [AgentActivity(session: session, project: "p", provider: "Claude", state: $0)] } ?? []
        return ActivitySnapshot(revision: 1, agents: agents, events: [])
    }

    func makeExecutor(_ muxy: FakeMuxy, timeout: Duration = .seconds(2)) -> AnswerExecutor {
        AnswerExecutor(muxy: muxy, stepDelay: .zero, confirmTimeout: timeout, pollEvery: .milliseconds(10))
    }

    func sends(_ muxy: FakeMuxy) async -> [String] {
        await muxy.calls.filter { $0.hasPrefix("send") }
    }

    @Test func approvesAndConfirms() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/permission-bash.txt")])
        await muxy.setActivity([snapshot(.blocked), snapshot(.working)])
        let outcome = await makeExecutor(muxy).perform(.option(1), pending: try pending("permission-request-bash"), session: session)
        #expect(outcome == .delivered)
        #expect(await sends(muxy) == ["send:s1:1"])
    }

    @Test func screenChangedBeforeSendSendsNothing() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/idle-after-deny.txt")])
        await muxy.setActivity([snapshot(.idle)])
        let outcome = await makeExecutor(muxy).perform(.option(1), pending: try pending("permission-request-bash"), session: session)
        #expect(outcome == .promptChanged)
        #expect(await sends(muxy).isEmpty)
    }

    @Test func unsupportedSendsNothing() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/question-single.txt")])
        let outcome = await makeExecutor(muxy).perform(.deny(feedback: "x"), pending: try pending("pre-tool-use-question-single"), session: session)
        #expect(outcome == .unsupported)
        #expect(await sends(muxy).isEmpty)
    }

    @Test func denyWaitsForIdleThenTypesFeedback() async throws {
        let muxy = FakeMuxy()
        let bash = try Fixture.text("screens/permission-bash.txt")
        await muxy.setScreens([bash, bash, try Fixture.text("screens/idle-after-deny.txt")])
        await muxy.setActivity([snapshot(.working)])
        let outcome = await makeExecutor(muxy).perform(.deny(feedback: "use trash"), pending: try pending("permission-request-bash"), session: session)
        #expect(outcome == .delivered)
        #expect(await sends(muxy) == ["send:s1:4", "send:s1:use trash", "sendKey:s1:Enter"])
    }

    @Test func idleNeverReachedIsNotConfirmed() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/permission-bash.txt")])
        await muxy.setActivity([snapshot(.working)])
        let outcome = await makeExecutor(muxy, timeout: .milliseconds(200)).perform(.deny(feedback: "x"), pending: try pending("permission-request-bash"), session: session)
        #expect(outcome == .notConfirmed)
        #expect(await sends(muxy) == ["send:s1:4"])
    }

    @Test func multiSelectWaitsForReview() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/question-multi.txt"), try Fixture.text("screens/question-submit-review.txt")])
        await muxy.setActivity([snapshot(.working)])
        let outcome = await makeExecutor(muxy).perform(.multiSelect([1]), pending: try pending("pre-tool-use-question-multi"), session: session)
        #expect(outcome == .delivered)
        #expect(await sends(muxy) == ["send:s1:1", "send:s1:\u{1B}[C", "send:s1:1"])
    }

    @Test func unconfirmedWhenStillBlocked() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/permission-bash.txt")])
        await muxy.setActivity([snapshot(.blocked)])
        let outcome = await makeExecutor(muxy, timeout: .milliseconds(400)).perform(.option(1), pending: try pending("permission-request-bash"), session: session)
        #expect(outcome == .notConfirmed)
    }

    @Test func activityFailureIsFailed() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/permission-bash.txt")])
        let outcome = await makeExecutor(muxy).perform(.option(1), pending: try pending("permission-request-bash"), session: session)
        guard case .failed = outcome else { Issue.record("expected failed, got \(outcome)"); return }
    }

    @Test func concurrentAnswerIsBusy() async throws {
        let muxy = FakeMuxy()
        await muxy.setScreens([try Fixture.text("screens/permission-bash.txt")])
        await muxy.setActivity([snapshot(.working)])
        let executor = makeExecutor(muxy)
        let item = try pending("permission-request-bash")
        async let a = executor.perform(.option(1), pending: item, session: session)
        async let b = executor.perform(.option(1), pending: item, session: session)
        let outcomes = await [a, b]
        #expect(outcomes.filter { $0 == .busy }.count == 1)
        #expect(outcomes.filter { $0 == .delivered }.count == 1)
        #expect(await sends(muxy) == ["send:s1:1"])
    }
}

import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct MuxyCLITests {
    private struct Harness {
        let dir: URL
        let log: URL
        let cli: MuxyCLI

        init(extra: String = "", timeout: Duration = .seconds(5)) throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            log = dir.appendingPathComponent("args.log")
            let fixtures = try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures/muxy").path
            let script = """
            #!/bin/sh
            for a in "$@"; do printf '%s\\n' "$a" >> "$MUXY_LOG"; done
            echo "@@END@@" >> "$MUXY_LOG"
            \(extra)
            case "$1 $2" in
            "activity list") cat "$FIXTURES/activity.json";;
            "session list") cat "$FIXTURES/session-list.json";;
            "project list") cat "$FIXTURES/project-list.json";;
            "server status") cat "$FIXTURES/server-status-running.json";;
            "session send") echo ok;;
            "session send-keys") echo ok;;
            "activity ack") echo ok;;
            esac
            """
            let exe = dir.appendingPathComponent("muxy")
            try script.write(to: exe, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
            cli = MuxyCLI(
                executable: exe,
                environment: ["MUXY_LOG": log.path, "FIXTURES": fixtures, "PATH": "/usr/bin:/bin"],
                timeout: timeout
            )
        }

        func calls() -> [[String]] {
            guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
            var result: [[String]] = []
            var current: [String] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
                if line == "@@END@@" {
                    result.append(current)
                    current = []
                } else {
                    current.append(String(line))
                }
            }
            return result
        }

        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    @Test func readsActivityAndLogsArguments() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let snapshot = try await h.cli.activity()
        #expect(snapshot.revision == 645)
        #expect(h.calls() == [["activity", "list", "--json"]])
    }

    @Test func readsSessionsProjectsAndBuildInfo() async throws {
        let h = try Harness(extra: "if [ \"$1\" = \"--build-info\" ]; then cat \"$FIXTURES/build-info.json\"; exit 0; fi")
        defer { h.cleanup() }
        #expect(try await !h.cli.sessions().isEmpty)
        #expect(try await !h.cli.projects().isEmpty)
        #expect(try await h.cli.buildInfo().isSupported)
        #expect(h.calls() == [["session", "list", "--json"], ["project", "list", "--json"], ["--build-info"]])
    }

    @Test func statusRunningAndStopped() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        #expect(await h.cli.serverStatus() == .running)
        #expect(h.calls() == [["server", "status", "--json"]])

        let stopped = try Harness(extra: "exit 1")
        defer { stopped.cleanup() }
        #expect(await stopped.cli.serverStatus() == .stopped)
    }

    @Test func statusStoppedOnBadJSON() async throws {
        let h = try Harness(extra: "echo 'not json'; exit 0")
        defer { h.cleanup() }
        #expect(await h.cli.serverStatus() == .stopped)
    }

    @Test func readScreenStateDecodesTextAndCursor() async throws {
        let h = try Harness(extra: "if [ \"$2\" = \"read-screen\" ]; then cat \"$FIXTURES/read-screen-idle-with-suggestion.json\"; exit 0; fi")
        defer { h.cleanup() }
        let state = try await h.cli.readScreenState(MuxySessionID("42"))
        #expect(state.cursorRow == 16)
        #expect(state.cursorCol == 2)
        #expect(state.text == (try Fixture.text("screens/idle-with-suggestion.txt")))
        #expect(h.calls() == [["session", "read-screen", "42", "--lines", "200", "--json"]])
    }

    @Test func readScreenStateHandlesLargeOutput() async throws {
        let big = "printf '{\"text\":\"'; yes 'line of screen text\\n' | head -n 20000 | tr -d '\\n'; printf '\",\"cursor\":{\"row\":3,\"col\":7}}'"
        let h = try Harness(extra: "if [ \"$2\" = \"read-screen\" ]; then \(big); exit 0; fi")
        defer { h.cleanup() }
        let state = try await h.cli.readScreenState(MuxySessionID("42"))
        #expect(state.text.split(separator: "\n").count == 20000)
        #expect(state.cursorRow == 3 && state.cursorCol == 7)
    }

    @Test func readScreenStateWithoutCursorThrows() async throws {
        let h = try Harness(extra: "if [ \"$2\" = \"read-screen\" ]; then echo '{\"text\":\"x\"}'; exit 0; fi")
        defer { h.cleanup() }
        await #expect(throws: (any Error).self) { try await h.cli.readScreenState(MuxySessionID("42")) }
    }

    @Test func sendPassesEscapeSequenceAsSingleArgument() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        try await h.cli.send(MuxySessionID("5602690846448319352"), text: "\u{1B}[C")
        #expect(h.calls() == [["session", "send", "5602690846448319352", "--", "\u{1B}[C"]])
    }

    @Test func sendSeparatesDashLeadingText() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        try await h.cli.send(MuxySessionID("5602690846448319352"), text: "-1 dash")
        #expect(h.calls() == [["session", "send", "5602690846448319352", "--", "-1 dash"]])
    }

    @Test func sendKeyAndAck() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        try await h.cli.sendKey(MuxySessionID("7"), .enter)
        try await h.cli.ack(eventIDs: ["e1", "e2"])
        try await h.cli.ack(eventIDs: [])
        #expect(h.calls() == [["session", "send-keys", "7", "Enter"], ["activity", "ack", "e1", "e2"]])
    }

    @Test func openInDesktopPassesDirectory() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        try await h.cli.openInDesktop(directory: "/Users/x/my project")
        #expect(h.calls() == [["/Users/x/my project"]])
    }

    @Test func nonZeroExitThrowsWithStderr() async throws {
        let h = try Harness(extra: "echo \"muxy: boom\" >&2; exit 1")
        defer { h.cleanup() }
        do {
            _ = try await h.cli.activity()
            Issue.record("expected throw")
        } catch let error as MuxyCommandError {
            #expect(error.exitCode == 1)
            #expect(error.stderr.contains("boom"))
            #expect(error.arguments == ["activity", "list", "--json"])
        }
    }

    @Test func timeoutKillsProcess() async throws {
        let h = try Harness(extra: "sleep 5", timeout: .milliseconds(300))
        defer { h.cleanup() }
        let start = ContinuousClock.now
        do {
            _ = try await h.cli.activity()
            Issue.record("expected throw")
        } catch let error as MuxyCommandError {
            #expect(error.exitCode == -1)
            #expect(error.stderr == "timed out")
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}

import Foundation
@testable import MuxyEyeCore

actor FakeMuxy: MuxyControlling {
    enum FakeError: Error { case noActivity }

    var status: MuxyServerStatus = .running
    var activityQueue: [ActivitySnapshot] = []
    var screens: [ScreenState] = []
    var sessionsResult: [MuxySessionInfo] = []
    var projectsResult: [MuxyProject] = []
    private(set) var calls: [String] = []

    private var activityIndex = 0
    private var screenIndex = 0

    func setStatus(_ status: MuxyServerStatus) { self.status = status }

    func setActivity(_ queue: [ActivitySnapshot]) {
        activityQueue = queue
        activityIndex = 0
    }

    /// Screens with the cursor where Claude's terminal leaves it: right after the marker
    /// of the last line that starts with "❯".
    func setScreens(_ texts: [String]) {
        setScreenStates(texts.map(Self.withClaudeCursor))
    }

    func setScreenStates(_ states: [ScreenState]) {
        screens = states
        screenIndex = 0
    }

    static func withClaudeCursor(_ text: String) -> ScreenState {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let row = lines.lastIndex { $0.hasPrefix("❯") } ?? max(lines.count - 1, 0)
        return ScreenState(text: text, cursorRow: row, cursorCol: 2)
    }

    func setSessions(_ sessions: [MuxySessionInfo]) { sessionsResult = sessions }
    func setProjects(_ projects: [MuxyProject]) { projectsResult = projects }

    func serverStatus() async -> MuxyServerStatus {
        calls.append("serverStatus")
        return status
    }

    func activity() async throws -> ActivitySnapshot {
        calls.append("activity")
        guard !activityQueue.isEmpty else { throw FakeError.noActivity }
        let snapshot = activityQueue[min(activityIndex, activityQueue.count - 1)]
        activityIndex += 1
        return snapshot
    }

    func sessions() async throws -> [MuxySessionInfo] {
        calls.append("sessions")
        return sessionsResult
    }

    func projects() async throws -> [MuxyProject] {
        calls.append("projects")
        return projectsResult
    }

    func readScreenState(_ session: MuxySessionID) async throws -> ScreenState {
        calls.append("readScreen:\(session.rawValue)")
        guard !screens.isEmpty else { return ScreenState(text: "", cursorRow: 0, cursorCol: 0) }
        let screen = screens[min(screenIndex, screens.count - 1)]
        screenIndex += 1
        return screen
    }

    func send(_ session: MuxySessionID, text: String) async throws {
        calls.append("send:\(session.rawValue):\(text)")
    }

    func sendKey(_ session: MuxySessionID, _ key: NamedKey) async throws {
        calls.append("sendKey:\(session.rawValue):\(key.rawValue)")
    }

    func ack(eventIDs: [String]) async throws {
        calls.append("ack:\(eventIDs.joined(separator: ","))")
    }

    func openInDesktop(directory: String) async throws {
        calls.append("open:\(directory)")
    }
}

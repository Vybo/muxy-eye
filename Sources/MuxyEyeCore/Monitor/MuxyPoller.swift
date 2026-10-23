import Foundation

public enum MuxyApp {
    public static let bundleIdentifiers: Set<String> = ["com.muxy.app", "com.muxy-beta.app"]
}

public struct MuxyPoller: Sendable {
    private let muxy: any MuxyControlling
    private let now: @Sendable () -> Date

    public init(muxy: any MuxyControlling, now: @escaping @Sendable () -> Date = Date.init) {
        self.muxy = muxy
        self.now = now
    }

    public func poll(includeMetadata: Bool) async -> [EyeAction] {
        guard await muxy.serverStatus() == .running else { return [.muxyStopped] }
        guard let snapshot = try? await muxy.activity() else { return [] }
        var actions: [EyeAction] = [.snapshot(snapshot, at: now())]
        if includeMetadata,
           let sessions = try? await muxy.sessions(),
           let projects = try? await muxy.projects() {
            actions.append(.metadata(sessions: sessions, projects: projects))
        }
        return actions
    }
}

public enum PollPolicy {
    public static func interval(for state: EyeState) -> Duration {
        let busy = state.sessions.values.contains {
            $0.muxyState == .working || $0.muxyState == .blocked || $0.pending != nil
        }
        return busy ? .seconds(1) : .seconds(3)
    }
}

public enum AutoExpandPolicy {
    public static func shouldExpand(
        effects: [EyeEffect],
        enabled: Bool,
        muxyFrontmost: Bool,
        panelExpanded: Bool
    ) -> Bool {
        guard enabled, !muxyFrontmost, !panelExpanded else { return false }
        return effects.contains { if case .becameWaiting = $0 { true } else { false } }
    }
}

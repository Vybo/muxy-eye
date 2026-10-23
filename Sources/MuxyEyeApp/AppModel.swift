import AppKit
import MuxyEyeCore
import Observation
import os

/// Shows and hides the eye's panel; implemented by the window controller.
@MainActor
protocol EyePresenting: AnyObject {
    func present(expanded: Bool, focus: Bool)
}

@MainActor @Observable
final class AppModel {
    private static let log = Logger(subsystem: "io.github.vybo.muxy-eye", category: "app")

    private(set) var state = EyeState()
    private(set) var expanded = false
    var selectedSession: MuxySessionID?
    private(set) var latestScreen: [MuxySessionID: String] = [:]
    private(set) var lastOutcome: [MuxySessionID: AnswerOutcome] = [:]
    private(set) var muxyFrontmost = false
    private(set) var muxyExecutable: URL?
    private(set) var buildInfo: MuxyBuildInfo?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored weak var presenter: (any EyePresenting)?

    @ObservationIgnored private var muxy: MuxyCLI?
    @ObservationIgnored private var executor: AnswerExecutor?
    @ObservationIgnored private var hookServer: HookSocketServer?
    @ObservationIgnored private var needsMetadata = true
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var hookTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let wakeStream: AsyncStream<Void>
    @ObservationIgnored private let wakeContinuation: AsyncStream<Void>.Continuation

    private let home = FileManager.default.homeDirectoryForCurrentUser

    init(settings: AppSettings) {
        self.settings = settings
        (wakeStream, wakeContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        refreshBundledHelper()
        observeFrontmostApp()
        connectMuxy()
        startHookServer()
        if muxy != nil {
            pollTask = Task { [weak self] in await self?.runPollLoop() }
            wake()
        }
    }

    func stop() {
        pollTask?.cancel()
        hookTask?.cancel()
        timerTask?.cancel()
        hookServer?.stop()
        hookServer = nil
    }

    // MARK: Panel

    func expand(focus: Bool) {
        if selectedSession.flatMap({ state.sessions[$0] }) == nil {
            let rail = state.rail
            selectedSession = (rail.first(where: state.isWaiting) ?? rail.first)?.id
        }
        expanded = true
        presenter?.present(expanded: true, focus: focus)
    }

    func collapse() {
        expanded = false
        presenter?.present(expanded: false, focus: false)
    }

    // MARK: Session actions

    func answer(_ answer: UserAnswer, for session: MuxySessionID) async {
        guard let executor else {
            lastOutcome[session] = .failed("Muxy not found")
            return
        }
        guard state.muxyRunning else {
            lastOutcome[session] = .failed("Muxy is not running")
            return
        }
        guard let pending = state.sessions[session]?.pending else {
            lastOutcome[session] = .promptChanged
            return
        }
        lastOutcome[session] = nil
        let outcome = await executor.perform(answer, pending: pending, session: session)
        lastOutcome[session] = outcome
        if outcome == .delivered {
            handle(EyeReducer.reduce(&state, .answered(session, at: .now)))
            wake()
        }
    }

    func dismiss(_ session: MuxySessionID) {
        handle(EyeReducer.reduce(&state, .dismiss(session, at: .now)))
    }

    func openInMuxy(_ session: MuxySessionID) async {
        if state.muxyRunning, let muxy {
            let directory = state.sessionInfo[session]?.directory ?? state.sessions[session]?.directory
            if let directory { try? await muxy.openInDesktop(directory: directory) }
        }
        activateMuxy()
        if state.muxyRunning, let muxy, let ids = state.sessions[session]?.unreadEventIDs, !ids.isEmpty {
            try? await muxy.ack(eventIDs: ids)
        }
    }

    func loadScreen(_ session: MuxySessionID) async {
        guard state.muxyRunning, let muxy else { return }
        if let screen = try? await muxy.readScreen(session) {
            latestScreen[session] = screen
        }
    }

    // MARK: Setup

    private func connectMuxy() {
        let override = settings.muxyPathOverride.flatMap(Self.expandingTilde)
        let executable = MuxyLocator.locate(
            home: home,
            override: override,
            pathVariable: ProcessInfo.processInfo.environment["PATH"]
        )
        muxyExecutable = executable
        guard let executable else { return }

        var environment = ProcessInfo.processInfo.environment
        if let profile = settings.muxyProfileDir.flatMap(Self.expandingTilde) {
            environment["MUXY_DIR"] = profile
        }
        let cli = MuxyCLI(executable: executable, environment: environment)
        muxy = cli
        executor = AnswerExecutor(muxy: cli)
        Task { [weak self] in
            let info = try? await cli.buildInfo()
            self?.buildInfo = info
        }
    }

    private func startHookServer() {
        let server = HookSocketServer(socketURL: HookWire.defaultSocketURL(home: home))
        let stream: AsyncStream<HookEnvelope>
        do {
            stream = try server.start()
        } catch {
            Self.log.error("Hook socket failed to start: \(String(describing: error), privacy: .public)")
            return
        }
        hookServer = server
        hookTask = Task { [weak self] in
            for await envelope in stream {
                self?.receive(envelope)
            }
        }
    }

    private func refreshBundledHelper() {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/muxy-eye-hook")
        guard FileManager.default.isExecutableFile(atPath: bundled.path) else { return }
        do {
            try HookInstaller.installHelper(from: bundled, to: HookWire.installedHelperURL(home: home))
        } catch {
            Self.log.error("Hook helper copy failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeFrontmostApp() {
        muxyFrontmost = Self.isMuxy(NSWorkspace.shared.frontmostApplication)
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isMuxy = Self.isMuxy(app)
            MainActor.assumeIsolated { self?.muxyFrontmost = isMuxy }
        }
        observers.append(token)
    }

    // MARK: Polling

    private func runPollLoop() async {
        for await _ in wakeStream {
            guard let muxy, !Task.isCancelled else { return }
            let includeMetadata = needsMetadata
            let actions = await MuxyPoller(muxy: muxy).poll(includeMetadata: includeMetadata)
            let gotMetadata = actions.contains { if case .metadata = $0 { true } else { false } }
            if gotMetadata { needsMetadata = false }

            var effects: [EyeEffect] = []
            for action in actions {
                effects += EyeReducer.reduce(&state, action)
            }
            if gotMetadata { effects.removeAll { $0 == .refreshMetadata } }
            handle(effects)
            scheduleNextPoll(after: PollPolicy.interval(for: state))
        }
    }

    private func scheduleNextPoll(after interval: Duration) {
        timerTask?.cancel()
        let continuation = wakeContinuation
        timerTask = Task {
            do {
                try await Task.sleep(for: interval)
                continuation.yield()
            } catch {}
        }
    }

    private func wake() {
        wakeContinuation.yield()
    }

    // MARK: Hooks and effects

    private func receive(_ envelope: HookEnvelope) {
        guard muxy != nil, let event = HookDecoder.decode(envelope) else { return }
        handle(EyeReducer.reduce(&state, .hook(event, at: .now)))
        wake()
    }

    private func handle(_ effects: [EyeEffect]) {
        for effect in effects {
            switch effect {
            case .ack(let eventIDs):
                guard state.muxyRunning, let muxy else { continue }
                Task { try? await muxy.ack(eventIDs: eventIDs) }
            case .refreshMetadata:
                needsMetadata = true
                wake()
            case .becameWaiting:
                break
            }
        }
        if AutoExpandPolicy.shouldExpand(
            effects: effects,
            enabled: settings.autoExpand,
            muxyFrontmost: muxyFrontmost,
            panelExpanded: expanded
        ) {
            expand(focus: false)
        }
    }

    // MARK: Helpers

    private func activateMuxy() {
        let app = MuxyApp.bundleIdentifiers.lazy
            .compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            .first
        app?.activate()
    }

    private nonisolated static func isMuxy(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return MuxyApp.bundleIdentifiers.contains(id)
    }

    private static func expandingTilde(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : (trimmed as NSString).expandingTildeInPath
    }
}

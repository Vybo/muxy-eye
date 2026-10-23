import AppKit
import MuxyEyeCore
import Observation
import os

/// Shows and hides the eye's panel; implemented by the window controller.
@MainActor
protocol EyePresenting: AnyObject {
    func present(expanded: Bool, focus: Bool)
    func hide(for duration: Duration)
}

/// A key the expanded panel handles while it is the key window.
enum PanelKey: Equatable {
    case digit(Int)
    case primary
    case up
    case down
    case escape
}

/// A key press for the selected prompt's view. The serial makes repeated presses of one key distinct.
struct PanelKeyPress: Equatable {
    enum Kind: Equatable {
        case digit(Int)
        case primary
    }

    let kind: Kind
    let serial: Int
}

@MainActor @Observable
final class AppModel {
    /// The `.failed` reason recorded when an answer finds the Muxy server stopped.
    nonisolated static let muxyNotRunningReason = "Muxy isn't running"

    private nonisolated static let log = Logger(subsystem: "io.github.vybo.muxy-eye", category: "app")
    private static let collapseDelay: Duration = .seconds(1)
    private static let muxyAppBundleIDs = ["com.muxy.app", "com.muxy-beta.app"]

    private(set) var state = EyeState()
    private(set) var expanded = false
    var selectedSession: MuxySessionID?
    private(set) var latestScreen: [MuxySessionID: ScreenState] = [:]
    private(set) var lastOutcome: [MuxySessionID: AnswerOutcome] = [:]
    private(set) var answering: Set<MuxySessionID> = []
    private(set) var keyPress: PanelKeyPress?
    private(set) var muxyFrontmost = false
    private(set) var muxyExecutable: URL?
    private(set) var buildInfo: MuxyBuildInfo?
    private(set) var hookStatus: HookInstallStatus?
    private(set) var hookError: String?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored weak var presenter: (any EyePresenting)?
    @ObservationIgnored var openSettings: () -> Void = {}

    @ObservationIgnored private var muxy: MuxyCLI?
    @ObservationIgnored private var executor: AnswerExecutor?
    @ObservationIgnored private var hookServer: HookSocketServer?
    @ObservationIgnored private var needsMetadata = true
    @ObservationIgnored private var started = false
    @ObservationIgnored private var keySerial = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var hookTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
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
        pollTask = Task { [weak self] in await self?.runPollLoop() }
        if muxy != nil { wake() }
        refreshHookStatus()
    }

    /// Looks for Muxy again after the path override or profile folder changed.
    func muxySettingsChanged() {
        muxy = nil
        executor = nil
        buildInfo = nil
        needsMetadata = true
        connectMuxy()
        if muxy != nil { wake() }
    }

    func hidePanel(for duration: Duration) {
        presenter?.hide(for: duration)
    }

    // MARK: Claude hooks

    var claudeSettingsURL: URL {
        ClaudeSettingsLocation.settingsURL(environment: ProcessInfo.processInfo.environment, home: home)
    }

    private var hookInstaller: HookInstaller {
        HookInstaller(settingsURL: claudeSettingsURL, helperURL: HookWire.installedHelperURL(home: home))
    }

    func refreshHookStatus() {
        do {
            hookStatus = try hookInstaller.status()
            hookError = nil
        } catch {
            hookStatus = nil
            hookError = SetupText.hookError(error)
        }
    }

    func installHooks() {
        do {
            let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/muxy-eye-hook")
            try HookInstaller.installHelper(from: bundled, to: HookWire.installedHelperURL(home: home))
            try hookInstaller.install()
            refreshHookStatus()
        } catch {
            hookError = SetupText.hookError(error)
        }
    }

    func removeHooks() {
        do {
            try hookInstaller.uninstall()
            refreshHookStatus()
        } catch {
            hookError = SetupText.hookError(error)
        }
    }

    func stop() {
        pollTask?.cancel()
        hookTask?.cancel()
        timerTask?.cancel()
        collapseTask?.cancel()
        hookServer?.stop()
        hookServer = nil
    }

    // MARK: Panel

    func expand(focus: Bool) {
        cancelPendingCollapse()
        let selected = selectedSession.flatMap { state.sessions[$0] }
        if selected.map(state.isWaiting) != true {
            let rail = state.rail
            if let waiting = rail.first(where: state.isWaiting) {
                selectedSession = waiting.id
            } else if selected == nil {
                selectedSession = rail.first?.id
            }
        }
        expanded = true
        presenter?.present(expanded: true, focus: focus)
    }

    func collapse() {
        cancelPendingCollapse()
        expanded = false
        lastOutcome = [:]
        keyPress = nil
        presenter?.present(expanded: false, focus: false)
    }

    func handleKey(_ key: PanelKey) {
        switch key {
        case .escape: collapse()
        case .up: moveSelection(by: -1)
        case .down: moveSelection(by: 1)
        case .digit(let number): publishKey(.digit(number))
        case .primary: publishKey(.primary)
        }
    }

    /// Selects a rail row and reads its screen again, so its options reflect the terminal now.
    func select(_ session: MuxySessionID) {
        selectedSession = session
        refreshSelectedScreen()
    }

    /// The panel just became the key window: the selected prompt may have changed while it wasn't.
    func panelBecameKey() {
        refreshSelectedScreen()
    }

    private func refreshSelectedScreen() {
        guard expanded, let id = selectedSession, let record = state.sessions[id], state.isWaiting(record) else { return }
        Task { await loadScreen(id) }
    }

    func moveSelection(by offset: Int) {
        let rail = state.rail
        guard !rail.isEmpty else { return }
        let current = selectedSession.flatMap { id in rail.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + offset, 0), rail.count - 1) } ?? 0
        selectedSession = rail[next].id
    }

    /// Whether the latest screen still shows the session's pending prompt (true when nothing is pending).
    func screenShowsPending(_ session: MuxySessionID) -> Bool {
        guard let pending = state.sessions[session]?.pending else { return true }
        guard let screen = latestScreen[session] else { return false }
        return AnswerPlanner.matches(
            pending,
            screen: ScreenParser.parse(screen.text),
            idlePrompt: screen.isAtIdlePrompt
        )
    }

    // MARK: Session actions

    /// Answers the prompt the user was shown. `displayed` is the pending item the view rendered and
    /// `question` the question text it showed; when the session's prompt has changed since, nothing is sent.
    func answer(_ answer: UserAnswer, to displayed: PendingItem, question: String? = nil, for session: MuxySessionID) async {
        guard let answer = answer.sanitized, !answering.contains(session) else { return }
        guard let executor, let muxy else {
            record(.failed("Muxy not found"), for: session)
            return
        }
        answering.insert(session)
        defer { answering.remove(session) }
        lastOutcome[session] = nil

        guard await muxy.serverStatus() == .running else {
            record(.failed(Self.muxyNotRunningReason), for: session)
            return
        }
        guard let pending = state.sessions[session]?.pending, pending.isSamePrompt(as: displayed) else {
            record(.promptChanged, for: session)
            await loadScreen(session)
            return
        }
        var target = pending
        if let question {
            guard let narrowed = pending.narrowed(toQuestion: question) else {
                record(.promptChanged, for: session)
                return
            }
            target = narrowed
        }
        let outcome = await executor.perform(answer, pending: target, session: session)
        record(outcome, for: session)
        if outcome == .delivered {
            if await showsNextQuestion(of: pending, session: session) { return }
            if state.sessions[session]?.pending?.isSamePrompt(as: displayed) == true {
                handle(apply([.answered(session, at: .now)]))
            }
            wake()
        } else {
            if case .failed(let reason) = outcome {
                Self.log.error("Answer failed for \(session.rawValue, privacy: .public): \(reason, privacy: .public)")
            }
            await loadScreen(session)
        }
    }

    /// Outcomes are feedback for the open panel; one that arrives after it collapsed is dropped.
    private func record(_ outcome: AnswerOutcome, for session: MuxySessionID) {
        lastOutcome[session] = expanded ? outcome : nil
    }

    /// After one of several questions is answered, Claude shows the next one. The pending item stays,
    /// so that question can be answered here too; it clears when Claude moves on.
    private func showsNextQuestion(of pending: PendingItem, session: MuxySessionID) async -> Bool {
        guard case .question(let request) = pending.kind, request.questions.count > 1 else { return false }
        await loadScreen(session)
        guard let screen = latestScreen[session] else { return false }
        return request.current(on: ScreenParser.parse(screen.text)) != nil
    }

    /// Dismisses the item the user was shown, never one that replaced it in the meantime.
    func dismiss(_ displayed: PendingItem, for session: MuxySessionID) {
        guard state.sessions[session]?.pending?.isSamePrompt(as: displayed) == true else { return }
        handle(apply([.dismiss(session, at: .now)]))
    }

    func openInMuxy(_ session: MuxySessionID) async {
        guard let muxy, await muxy.serverStatus() == .running else { return }
        if let directory = state.sessionInfo[session]?.directory ?? state.sessions[session]?.directory {
            do {
                try await muxy.openInDesktop(directory: directory)
            } catch {
                Self.log.error("Opening \(directory, privacy: .public) in Muxy failed: \(String(describing: error), privacy: .public)")
            }
        }
        bringMuxyForward()
        let eventIDs = state.sessions[session]?.unreadEventIDs ?? []
        if !eventIDs.isEmpty {
            do {
                try await muxy.ack(eventIDs: eventIDs)
            } catch {
                Self.log.error("Ack failed: \(String(describing: error), privacy: .public)")
            }
            wake()
        }
        collapse()
    }

    func loadScreen(_ session: MuxySessionID) async {
        guard let muxy, await muxy.serverStatus() == .running else { return }
        do {
            latestScreen[session] = try await muxy.readScreenState(session)
        } catch {
            Self.log.error("read-screen failed for \(session.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
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
            do {
                let info = try await cli.buildInfo()
                self?.buildInfo = info
            } catch {
                Self.log.error("muxy --build-info failed: \(String(describing: error), privacy: .public)")
            }
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
            guard !Task.isCancelled else { return }
            guard let muxy else { continue }
            let includeMetadata = needsMetadata
            let actions = await MuxyPoller(muxy: muxy).poll(includeMetadata: includeMetadata)
            let gotMetadata = actions.contains { if case .metadata = $0 { true } else { false } }
            if gotMetadata { needsMetadata = false }

            var effects = apply(actions)
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
        handle(apply([.hook(event, at: .now)]))
        wake()
    }

    /// Reduces the actions, then keeps the panel's selection, banners and auto-collapse in step.
    private func apply(_ actions: [EyeAction]) -> [EyeEffect] {
        let before = state
        var effects: [EyeEffect] = []
        for action in actions {
            effects += EyeReducer.reduce(&state, action)
        }
        guard state != before else { return effects }
        if before.sessions.keys.contains(where: { state.sessions[$0] == nil }) {
            latestScreen = latestScreen.filter { state.sessions[$0.key] != nil }
        }
        dropStaleOutcomes(before: before)
        reconcileSelection(previouslyWaiting: Set(before.sessions.values.filter(before.isWaiting).map(\.id)))
        if state.waitingCount > 0 {
            cancelPendingCollapse()
        } else if before.waitingCount > 0, expanded, !selectedShowsBanner {
            scheduleCollapse()
        }
        return effects
    }

    private func handle(_ effects: [EyeEffect]) {
        for effect in effects {
            switch effect {
            case .ack(let eventIDs):
                guard state.muxyRunning, let muxy else { continue }
                Task {
                    guard await muxy.serverStatus() == .running else { return }
                    do {
                        try await muxy.ack(eventIDs: eventIDs)
                    } catch {
                        Self.log.error("Ack failed: \(String(describing: error), privacy: .public)")
                    }
                }
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

    // MARK: Panel bookkeeping

    /// A banner belongs to the prompt it answered: it goes when another prompt arrives or the session ends.
    private func dropStaleOutcomes(before: EyeState) {
        for id in Array(lastOutcome.keys) {
            guard let record = state.sessions[id] else {
                lastOutcome[id] = nil
                continue
            }
            guard let pending = record.pending else { continue }
            if before.sessions[id]?.pending?.isSamePrompt(as: pending) != true {
                lastOutcome[id] = nil
            }
        }
    }

    /// Keeps a valid selection, and moves it to the first waiting row when the selected row
    /// stops waiting or another row starts.
    private func reconcileSelection(previouslyWaiting: Set<MuxySessionID>) {
        let rail = state.rail
        let firstWaiting = rail.first(where: state.isWaiting)
        guard let id = selectedSession, let record = state.sessions[id] else {
            selectedSession = (firstWaiting ?? rail.first)?.id
            return
        }
        guard !state.isWaiting(record), let firstWaiting else { return }
        let stoppedWaiting = previouslyWaiting.contains(id)
        let startedWaiting = rail.contains { state.isWaiting($0) && !previouslyWaiting.contains($0.id) }
        if stoppedWaiting || startedWaiting {
            selectedSession = firstWaiting.id
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.collapseDelay)
            } catch {
                return
            }
            // An outcome banner on the selected session holds the panel open so it can be read.
            guard let self, !self.selectedShowsBanner else { return }
            self.collapse()
        }
    }

    private var selectedShowsBanner: Bool {
        guard let id = selectedSession else { return false }
        return AnswerBanner.message(for: lastOutcome[id]) != nil
    }

    private func cancelPendingCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func publishKey(_ kind: PanelKeyPress.Kind) {
        keySerial += 1
        keyPress = PanelKeyPress(kind: kind, serial: keySerial)
    }

    // MARK: Helpers

    /// Brings the Muxy app forward: the running copy if there is one, else the installed Stable or Beta app.
    private func bringMuxyForward() {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.first { Self.isMuxy($0) }?.bundleURL
        let installed = Self.muxyAppBundleIDs.lazy.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }.first
        guard let url = running ?? installed else {
            Self.log.error("Muxy app not found")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Self.log.error("Activating Muxy failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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

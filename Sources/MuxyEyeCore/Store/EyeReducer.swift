import Foundation

public enum EyeAction: Sendable {
    case snapshot(ActivitySnapshot, at: Date)
    case metadata(sessions: [MuxySessionInfo], projects: [MuxyProject])
    case hook(HookEvent, at: Date)
    case muxyStopped
    case dismiss(MuxySessionID, at: Date)
    case answered(MuxySessionID, at: Date)
}

public enum EyeEffect: Sendable, Equatable {
    case becameWaiting(MuxySessionID)
    case ack(eventIDs: [String])
    case refreshMetadata
}

public enum EyeReducer {
    public static let provisionalGrace: TimeInterval = 5
    public static let neverBlockedExpiry: TimeInterval = 10
    public static let finishedGrace: TimeInterval = 5
    private static let finishedEventSkew: TimeInterval = 2

    public static func reduce(_ state: inout EyeState, _ action: EyeAction) -> [EyeEffect] {
        switch action {
        case let .snapshot(snapshot, now):
            return reduceSnapshot(&state, snapshot, now)
        case let .metadata(sessions, projects):
            state.sessionInfo = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            state.projects = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            for id in Array(state.sessions.keys) {
                if var record = state.sessions[id] {
                    applyNames(state, &record)
                    state.sessions[id] = record
                }
            }
            return []
        case let .hook(event, now):
            return reduceHook(&state, event, now)
        case .muxyStopped:
            state = EyeState()
            return []
        case let .dismiss(id, _):
            return clearAndAck(&state, id, clearsPrompt: { _ in true })
        case let .answered(id, _):
            return clearAndAck(&state, id, clearsPrompt: { kind in
                if case .finished = kind { return false }
                return true
            })
        }
    }

    private static func clearAndAck(
        _ state: inout EyeState,
        _ id: MuxySessionID,
        clearsPrompt: (PendingKind) -> Bool
    ) -> [EyeEffect] {
        guard var record = state.sessions[id] else { return [] }
        if let pending = record.pending, clearsPrompt(pending.kind) { record.pending = nil }
        let ids = record.unreadEventIDs
        record.unreadEventIDs = []
        record.unreadCompletedEventID = nil
        record.unreadCompletedAt = nil
        state.sessions[id] = record
        return ids.isEmpty ? [] : [.ack(eventIDs: ids)]
    }

    // MARK: Snapshot

    private static func reduceSnapshot(_ state: inout EyeState, _ snapshot: ActivitySnapshot, _ now: Date) -> [EyeEffect] {
        var effects: [EyeEffect] = []
        state.muxyRunning = true
        let present = Set(snapshot.agents.map(\.session))
        var sawNewSession = false

        for agent in snapshot.agents {
            let existing = state.sessions[agent.session]
            if existing == nil || existing?.provisionalSince != nil { sawNewSession = true }
            let wasWaiting = existing.map(state.isWaiting) ?? false
            var record = existing ?? SessionRecord(id: agent.session, provider: agent.provider, projectID: agent.project)
            record.provider = agent.provider
            record.provisionalSince = nil
            if state.sessionInfo[agent.session] == nil { record.projectID = agent.project }

            record.muxyState = agent.state
            if agent.state == .blocked {
                record.blockedSince = record.blockedSince ?? now
            } else {
                record.blockedSince = nil
            }

            let unread = snapshot.events.filter { $0.session == agent.session && !$0.read }
            record.unreadEventIDs = unread.map(\.id)
            let completed = unread.first { $0.kind == .completed }
            record.unreadCompletedEventID = completed?.id
            record.unreadCompletedAt = completed.map { Date(timeIntervalSince1970: TimeInterval($0.timestamp)) }

            let completedEvents = snapshot.events.filter { $0.session == agent.session && $0.kind == .completed }
            updatePending(&record, completedEvents: completedEvents, now: now)
            applyNames(state, &record)
            state.sessions[agent.session] = record

            if !wasWaiting, state.isWaiting(record) { effects.append(.becameWaiting(agent.session)) }
        }

        for (id, record) in state.sessions where !present.contains(id) {
            if let since = record.provisionalSince, now.timeIntervalSince(since) <= provisionalGrace { continue }
            state.sessions[id] = nil
        }
        if sawNewSession { effects.append(.refreshMetadata) }
        return effects
    }

    private static func updatePending(_ record: inout SessionRecord, completedEvents: [ActivityEvent], now: Date) {
        guard var pending = record.pending else { return }
        switch pending.kind {
        case .permission, .question:
            if record.muxyState == .blocked { pending.sawBlocked = true }
            let settled = record.muxyState == .working || record.muxyState == .idle
            let resolved = pending.sawBlocked && settled
            let expired = !pending.sawBlocked && settled && now.timeIntervalSince(pending.receivedAt) > neverBlockedExpiry
            record.pending = (resolved || expired) ? nil : pending
        case .finished:
            let threshold = pending.receivedAt.timeIntervalSince1970 - finishedEventSkew
            let relevant = completedEvents.filter { TimeInterval($0.timestamp) >= threshold }
            let confirmedRead = relevant.contains { $0.read }
            let hasUnread = relevant.contains { !$0.read }
            let graceOver = now.timeIntervalSince(pending.receivedAt) > finishedGrace
            record.pending = (confirmedRead || (!hasUnread && graceOver)) ? nil : pending
        }
    }

    // MARK: Hooks

    private static func reduceHook(_ state: inout EyeState, _ hook: HookEvent, _ now: Date) -> [EyeEffect] {
        let id = hook.muxySession
        var record = state.sessions[id] ?? SessionRecord(
            id: id,
            provider: "Claude",
            projectID: state.sessionInfo[id]?.projectID ?? "",
            provisionalSince: now
        )
        if let claudeID = hook.claudeSessionID { record.claudeSessionID = claudeID }
        var effects: [EyeEffect] = []

        switch hook.event {
        case let .sessionStart(claudeSessionID):
            record.claudeSessionID = claudeSessionID
        case .sessionEnd:
            record.claudeSessionID = nil
            record.pending = nil
        case .userPromptSubmit:
            record.pending = nil
        case let .permission(request):
            record.pending = PendingItem(kind: .permission(request), receivedAt: now, sawBlocked: record.muxyState == .blocked)
            effects.append(.becameWaiting(id))
        case let .question(request):
            record.pending = PendingItem(kind: .question(request), receivedAt: now, sawBlocked: record.muxyState == .blocked)
            effects.append(.becameWaiting(id))
        case let .postToolUse(use):
            if let pending = record.pending, pending.kind.isCompleted(by: use) { record.pending = nil }
        case .notification:
            break
        case let .stop(message):
            if let message { record.lastAssistantMessage = message }
            record.pending = PendingItem(kind: .finished(message: message), receivedAt: now, sawBlocked: false)
            effects.append(.becameWaiting(id))
        }

        applyNames(state, &record)
        state.sessions[id] = record
        return effects
    }

    // MARK: Names

    private static func applyNames(_ state: EyeState, _ record: inout SessionRecord) {
        let info = state.sessionInfo[record.id]
        let projectID = info?.projectID ?? record.projectID
        record.projectID = projectID
        record.directory = info?.directory ?? record.directory
        guard let project = state.projects[projectID] else { return }
        if project.kind == "worktree", let parent = project.parentID.flatMap({ state.projects[$0] }) {
            record.projectName = parent.name
            record.subtitle = project.name
        } else {
            record.projectName = project.name
            record.subtitle = nil
        }
    }
}

private extension PendingKind {
    /// Whether this finished tool call is the one the prompt asked about. Other tools, including
    /// those of parallel subagents, finish in the same session while a prompt is open.
    func isCompleted(by use: ToolUse) -> Bool {
        switch self {
        case let .permission(request):
            return use.toolName == request.toolName
                && use.toolInput == request.toolInput
                && use.agentID == request.agentID
        case let .question(request):
            guard use.toolName == HookDecoder.askUserQuestion else { return false }
            guard let asked = request.toolUseID, let finished = use.toolUseID else { return true }
            return asked == finished
        case .finished:
            return false
        }
    }
}

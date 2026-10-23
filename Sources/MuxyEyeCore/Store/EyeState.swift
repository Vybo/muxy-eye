import Foundation

public enum PendingKind: Sendable, Equatable {
    case permission(PermissionRequest)
    case question(QuestionRequest)
    case finished(message: String?)
}

public struct PendingItem: Sendable, Equatable {
    public var kind: PendingKind
    public var receivedAt: Date
    public var sawBlocked: Bool

    public init(kind: PendingKind, receivedAt: Date, sawBlocked: Bool) {
        self.kind = kind
        self.receivedAt = receivedAt
        self.sawBlocked = sawBlocked
    }
}

extension PendingItem {
    /// The same prompt: same content and arrival. Whether Muxy has seen the session blocked yet doesn't matter.
    public func isSamePrompt(as other: PendingItem) -> Bool {
        kind == other.kind && receivedAt == other.receivedAt
    }

    /// The item reduced to the one question the user was shown, so an answer can't land on another
    /// question of the same request. Nil when the item isn't a question or doesn't contain that question.
    public func narrowed(toQuestion text: String) -> PendingItem? {
        guard case .question(let request) = kind,
              let question = request.questions.first(where: { $0.question == text })
        else { return nil }
        let single = QuestionRequest(questions: [question], toolUseID: request.toolUseID)
        return PendingItem(kind: .question(single), receivedAt: receivedAt, sawBlocked: sawBlocked)
    }
}

public struct SessionRecord: Sendable, Equatable, Identifiable {
    public var id: MuxySessionID
    public var provider: String
    public var projectID: String
    public var projectName: String
    public var subtitle: String?
    public var directory: String?
    public var muxyState: AgentState
    public var blockedSince: Date?
    public var claudeSessionID: String?
    public var pending: PendingItem?
    public var lastAssistantMessage: String?
    public var unreadEventIDs: [String]
    public var unreadCompletedEventID: String?
    public var unreadCompletedAt: Date?
    public var provisionalSince: Date?

    public init(
        id: MuxySessionID,
        provider: String,
        projectID: String,
        projectName: String = "",
        subtitle: String? = nil,
        directory: String? = nil,
        muxyState: AgentState = .unknown,
        blockedSince: Date? = nil,
        claudeSessionID: String? = nil,
        pending: PendingItem? = nil,
        lastAssistantMessage: String? = nil,
        unreadEventIDs: [String] = [],
        unreadCompletedEventID: String? = nil,
        unreadCompletedAt: Date? = nil,
        provisionalSince: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.projectID = projectID
        self.projectName = projectName
        self.subtitle = subtitle
        self.directory = directory
        self.muxyState = muxyState
        self.blockedSince = blockedSince
        self.claudeSessionID = claudeSessionID
        self.pending = pending
        self.lastAssistantMessage = lastAssistantMessage
        self.unreadEventIDs = unreadEventIDs
        self.unreadCompletedEventID = unreadCompletedEventID
        self.unreadCompletedAt = unreadCompletedAt
        self.provisionalSince = provisionalSince
    }

    public var isClaude: Bool { provider == "Claude" }
}

public enum EyeMode: Sendable, Equatable {
    case idle, working, waiting
}

public struct EyeState: Sendable, Equatable {
    public var sessions: [MuxySessionID: SessionRecord]
    public var muxyRunning: Bool
    public var projects: [String: MuxyProject]
    public var sessionInfo: [MuxySessionID: MuxySessionInfo]

    public init(
        sessions: [MuxySessionID: SessionRecord] = [:],
        muxyRunning: Bool = false,
        projects: [String: MuxyProject] = [:],
        sessionInfo: [MuxySessionID: MuxySessionInfo] = [:]
    ) {
        self.sessions = sessions
        self.muxyRunning = muxyRunning
        self.projects = projects
        self.sessionInfo = sessionInfo
    }

    public func isWaiting(_ r: SessionRecord) -> Bool {
        r.muxyState == .blocked || r.pending != nil || (!r.isClaude && r.unreadCompletedEventID != nil)
    }

    public func waitingSince(_ r: SessionRecord) -> Date? {
        r.pending?.receivedAt ?? r.blockedSince ?? r.unreadCompletedAt
    }

    public var mode: EyeMode {
        if sessions.values.contains(where: isWaiting) { return .waiting }
        if sessions.values.contains(where: { $0.muxyState == .working }) { return .working }
        return .idle
    }

    public var waitingCount: Int {
        sessions.values.filter(isWaiting).count
    }

    public var rail: [SessionRecord] {
        func group(_ r: SessionRecord) -> Int {
            if isWaiting(r) { return 0 }
            return r.muxyState == .working ? 1 : 2
        }
        return sessions.values.sorted { a, b in
            let ga = group(a), gb = group(b)
            if ga != gb { return ga < gb }
            if ga == 0 {
                let wa = waitingSince(a) ?? .distantPast, wb = waitingSince(b) ?? .distantPast
                if wa != wb { return wa < wb }
            }
            if a.projectName != b.projectName { return a.projectName < b.projectName }
            return a.id.rawValue < b.id.rawValue
        }
    }
}

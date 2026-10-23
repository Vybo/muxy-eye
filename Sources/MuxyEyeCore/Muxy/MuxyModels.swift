import Foundation

public struct MuxySessionID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public enum AgentState: String, Sendable, Decodable {
    case unknown, idle, working, blocked

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentState(rawValue: raw.lowercased()) ?? .unknown
    }
}

public enum ActivityEventKind: Sendable, Equatable, Decodable {
    case attention
    case completed
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "attention": self = .attention
        case "completed": self = .completed
        default: self = .other(raw)
        }
    }
}

public struct AgentActivity: Decodable, Sendable, Equatable {
    public let session: MuxySessionID
    public let project: String
    public let provider: String
    public let state: AgentState

    public var isClaude: Bool { provider == "Claude" }
}

public struct ActivityEvent: Decodable, Sendable, Equatable {
    public let id: String
    public let session: MuxySessionID
    public let project: String
    public let provider: String
    public let timestamp: Int64
    public let kind: ActivityEventKind
    public let read: Bool
}

public struct ActivitySnapshot: Decodable, Sendable, Equatable {
    public let revision: UInt64
    public let agents: [AgentActivity]
    public let events: [ActivityEvent]
}

public struct MuxySessionInfo: Decodable, Sendable, Equatable {
    public let id: MuxySessionID
    public let projectID: String
    public let directory: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, directory, status
        case projectID = "project_id"
    }
}

public struct MuxyProject: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let directory: String
    public let parentID: String?
    /// `"worktree"` for worktrees; Muxy reports null (or `"project"`) for top-level projects.
    public let kind: String?

    enum CodingKeys: String, CodingKey {
        case id, name, directory, kind
        case parentID = "parent_id"
    }
}

public struct MuxyBuildInfo: Decodable, Sendable, Equatable {
    public let version: String
    public let compatibility: Int
    public let protocolVersions: [Int]

    enum CodingKeys: String, CodingKey {
        case version, compatibility
        case protocolVersions = "protocol"
    }

    public var isSupported: Bool { protocolVersions.contains(2) }
}

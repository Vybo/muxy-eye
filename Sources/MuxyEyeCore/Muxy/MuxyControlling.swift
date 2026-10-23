import Foundation

public enum MuxyServerStatus: Sendable, Equatable {
    case running
    case stopped
}

public struct MuxyCommandError: Error, Equatable, Sendable {
    public let arguments: [String]
    public let exitCode: Int32
    public let stderr: String

    public init(arguments: [String], exitCode: Int32, stderr: String) {
        self.arguments = arguments
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

public protocol MuxyControlling: Sendable {
    func serverStatus() async -> MuxyServerStatus
    func activity() async throws -> ActivitySnapshot
    func sessions() async throws -> [MuxySessionInfo]
    func projects() async throws -> [MuxyProject]
    func readScreen(_ session: MuxySessionID) async throws -> String
    func send(_ session: MuxySessionID, text: String) async throws
    func sendKey(_ session: MuxySessionID, _ key: NamedKey) async throws
    func ack(eventIDs: [String]) async throws
    func openInDesktop(directory: String) async throws
}

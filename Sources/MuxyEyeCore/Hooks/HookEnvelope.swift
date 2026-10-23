import Foundation

public struct HookEnvelope: Codable, Sendable, Equatable {
    public var v: Int
    public var event: String
    public var muxySessionID: MuxySessionID
    public var muxyServerID: String?
    public var payload: JSONValue

    public init(v: Int, event: String, muxySessionID: MuxySessionID, muxyServerID: String?, payload: JSONValue) {
        self.v = v
        self.event = event
        self.muxySessionID = muxySessionID
        self.muxyServerID = muxyServerID
        self.payload = payload
    }
}

public enum HookWire {
    public static let version = 1
    public static let socketEnvironmentKey = "MUXY_EYE_SOCKET"

    public static func supportDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Muxy Eye", isDirectory: true)
    }

    public static func defaultSocketURL(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("eye.sock")
    }

    public static func installedHelperURL(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("bin/muxy-eye-hook")
    }
}

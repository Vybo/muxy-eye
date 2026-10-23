import Darwin
import Foundation

public enum HookForwarder {
    @discardableResult
    public static func forward(
        event: String,
        stdin: Data,
        environment: [String: String],
        home: URL,
        timeout: Duration = .milliseconds(200)
    ) -> Bool {
        guard let sessionID = environment["MUXY_SESSION_ID"], !sessionID.isEmpty,
              let payload = try? JSONDecoder().decode(JSONValue.self, from: stdin)
        else { return false }

        let envelope = HookEnvelope(
            v: HookWire.version,
            event: event,
            muxySessionID: MuxySessionID(sessionID),
            muxyServerID: environment["MUXY_SERVER_ID"],
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard var line = try? encoder.encode(envelope) else { return false }
        line.append(0x0A)

        let socketPath = environment[HookWire.socketEnvironmentKey] ?? HookWire.defaultSocketURL(home: home).path
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }

        let components = timeout.components
        let totalMs = max(1, Int(components.seconds) * 1000 + Int(components.attoseconds / 1_000_000_000_000_000))
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(totalMs) * 1_000_000
        return send(line, to: socketPath, deadline: deadline)
    }

    private static func remainingMs(_ deadline: UInt64) -> Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { return 0 }
        return Int32(min((deadline - now + 999_999) / 1_000_000, 1000))
    }

    private static func send(_ data: Data, to path: String, deadline: UInt64) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        guard UnixSocket.configureNonBlockingNoSigPipe(fd),
              var address = UnixSocket.address(path)
        else { return false }

        var connected = false
        while !connected {
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result == 0 || errno == EISCONN {
                connected = true
            } else if errno == EINTR || errno == EAGAIN || errno == EINPROGRESS || errno == EALREADY {
                let wait = remainingMs(deadline)
                guard wait > 0 else { return false }
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&descriptor, 1, min(wait, 5))
            } else {
                return false
            }
        }

        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written > 0 {
                offset += written
            } else if written < 0 && (errno == EAGAIN || errno == EINTR) {
                let wait = remainingMs(deadline)
                guard wait > 0 else { return false }
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&descriptor, 1, wait)
            } else {
                return false
            }
        }
        return true
    }
}

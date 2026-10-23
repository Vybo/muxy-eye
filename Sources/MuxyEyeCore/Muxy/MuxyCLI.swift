import Foundation

public struct MuxyCLI: MuxyControlling {
    private let executable: URL
    private let environment: [String: String]
    private let timeout: Duration

    public init(
        executable: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(5)
    ) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
    }

    public func serverStatus() async -> MuxyServerStatus {
        guard let data = try? await run(["server", "status", "--json"]),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["instance"] != nil
        else { return .stopped }
        return .running
    }

    public func activity() async throws -> ActivitySnapshot {
        try decode(ActivitySnapshot.self, from: await run(["activity", "list", "--json"]))
    }

    public func sessions() async throws -> [MuxySessionInfo] {
        try decode([MuxySessionInfo].self, from: await run(["session", "list", "--json"]))
    }

    public func projects() async throws -> [MuxyProject] {
        try decode([MuxyProject].self, from: await run(["project", "list", "--json"]))
    }

    public func buildInfo() async throws -> MuxyBuildInfo {
        try decode(MuxyBuildInfo.self, from: await run(["--build-info"]))
    }

    public func readScreen(_ session: MuxySessionID) async throws -> String {
        let data = try await run(["session", "read-screen", session.rawValue, "--lines", "200"])
        return String(decoding: data, as: UTF8.self)
    }

    public func send(_ session: MuxySessionID, text: String) async throws {
        _ = try await run(["session", "send", session.rawValue, "--", text])
    }

    public func sendKey(_ session: MuxySessionID, _ key: NamedKey) async throws {
        _ = try await run(["session", "send-keys", session.rawValue, key.rawValue])
    }

    public func ack(eventIDs: [String]) async throws {
        guard !eventIDs.isEmpty else { return }
        _ = try await run(["activity", "ack"] + eventIDs)
    }

    public func openInDesktop(directory: String) async throws {
        _ = try await run([directory])
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let executable = executable
        let environment = environment
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        return try await withCheckedThrowingContinuation { continuation in
            ProcessRun.start(
                executable: executable,
                arguments: arguments,
                environment: environment,
                timeout: seconds,
                continuation: continuation
            )
        }
    }
}

private final class ProcessRun: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var timedOut = false
    private var continuation: CheckedContinuation<Data, Error>?
    private let arguments: [String]

    private init(arguments: [String], continuation: CheckedContinuation<Data, Error>) {
        self.arguments = arguments
        self.continuation = continuation
    }

    static func start(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        continuation: CheckedContinuation<Data, Error>
    ) {
        let run = ProcessRun(arguments: arguments, continuation: continuation)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        for handle in [outHandle, errHandle] {
            let flags = fcntl(handle.fileDescriptor, F_GETFL)
            _ = fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        }
        outHandle.readabilityHandler = { _ in run.drain(outHandle, errHandle) }
        errHandle.readabilityHandler = { _ in run.drain(outHandle, errHandle) }

        process.terminationHandler = { process in
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            run.drain(outHandle, errHandle)
            run.finish(exitCode: process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            run.resume(with: .failure(MuxyCommandError(
                arguments: arguments,
                exitCode: -1,
                stderr: error.localizedDescription
            )))
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning else { return }
            run.markTimedOut()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    private func drain(_ out: FileHandle, _ err: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        Self.readAvailable(out.fileDescriptor, into: &stdout)
        Self.readAvailable(err.fileDescriptor, into: &stderr)
    }

    private static func readAvailable(_ fd: Int32, into buffer: inout Data) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                buffer.append(chunk, count: count)
            } else {
                return
            }
        }
    }

    private func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    private func finish(exitCode: Int32) {
        lock.lock()
        let out = stdout
        let err = String(decoding: stderr, as: UTF8.self)
        let didTimeOut = timedOut
        lock.unlock()
        if didTimeOut {
            resume(with: .failure(MuxyCommandError(arguments: arguments, exitCode: -1, stderr: "timed out")))
        } else if exitCode != 0 {
            resume(with: .failure(MuxyCommandError(arguments: arguments, exitCode: exitCode, stderr: err)))
        } else {
            resume(with: .success(out))
        }
    }

    private func resume(with result: Result<Data, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

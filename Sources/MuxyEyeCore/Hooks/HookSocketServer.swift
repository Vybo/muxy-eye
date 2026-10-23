import Darwin
import Foundation

public final class HookSocketServer: @unchecked Sendable {
    public enum ServerError: Error {
        case pathTooLong
        case syscall(String, Int32)
    }

    private final class Connection {
        let fd: Int32
        var buffer = Data()
        var source: DispatchSourceRead?
        init(fd: Int32) { self.fd = fd }
    }

    private let socketURL: URL
    private let queue = DispatchQueue(label: "muxy-eye.hook-socket")
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]
    private var continuation: AsyncStream<HookEnvelope>.Continuation?

    public init(socketURL: URL) {
        self.socketURL = socketURL
    }

    public func start() throws -> AsyncStream<HookEnvelope> {
        let path = socketURL.path
        let directory = socketURL.deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        unlink(path)

        guard var address = UnixSocket.address(path) else { throw ServerError.pathTooLong }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.syscall("socket", errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw ServerError.syscall("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw ServerError.syscall("listen", code)
        }
        UnixSocket.configureNonBlockingNoSigPipe(fd)

        let (stream, continuation) = AsyncStream<HookEnvelope>.makeStream()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        queue.sync {
            self.listenFD = fd
            self.continuation = continuation
            self.listenSource = source
        }
        source.resume()
        return stream
    }

    public func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
            if listenFD >= 0 {
                close(listenFD)
                listenFD = -1
                unlink(socketURL.path)
            }
            for connection in connections.values {
                connection.source?.cancel()
                close(connection.fd)
            }
            connections.removeAll()
            continuation?.finish()
            continuation = nil
        }
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            UnixSocket.configureNonBlockingNoSigPipe(client)
            let connection = Connection(fd: client)
            let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
            source.setEventHandler { [weak self] in self?.read(connection) }
            connection.source = source
            connections[client] = connection
            source.resume()
        }
    }

    private func read(_ connection: Connection) {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(connection.fd, &chunk, chunk.count)
            if count > 0 {
                connection.buffer.append(contentsOf: chunk[0..<count])
                drainLines(of: connection)
            } else if count == 0 {
                drainLines(of: connection)
                if !connection.buffer.isEmpty { emit(connection.buffer) }
                finish(connection)
                return
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else if errno != EINTR {
                finish(connection)
                return
            }
        }
    }

    private func drainLines(of connection: Connection) {
        while let newline = connection.buffer.firstIndex(of: 0x0A) {
            let line = connection.buffer[connection.buffer.startIndex..<newline]
            emit(Data(line))
            connection.buffer.removeSubrange(connection.buffer.startIndex...newline)
        }
    }

    private func emit(_ line: Data) {
        guard !line.isEmpty,
              let envelope = try? JSONDecoder().decode(HookEnvelope.self, from: line)
        else { return }
        continuation?.yield(envelope)
    }

    private func finish(_ connection: Connection) {
        connection.source?.cancel()
        connection.source = nil
        if connections.removeValue(forKey: connection.fd) != nil {
            close(connection.fd)
        }
    }
}

import Darwin
import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct HookWireTests {
    private func socketURL() -> URL {
        let suffix = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("mxe-\(suffix)", isDirectory: true)
            .appendingPathComponent("eye.sock")
    }

    private func stopPayload() throws -> Data {
        let envelope = try JSONDecoder().decode(HookEnvelope.self, from: Fixture.data("hooks/stop.json"))
        return try JSONEncoder().encode(envelope.payload)
    }

    private func first(_ stream: AsyncStream<HookEnvelope>) async -> HookEnvelope? {
        await withTaskGroup(of: HookEnvelope?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    @Test func forwardedEventArrives() async throws {
        let url = socketURL()
        let server = HookSocketServer(socketURL: url)
        let stream = try server.start()
        defer { server.stop() }

        let sent = HookForwarder.forward(
            event: "Stop",
            stdin: try stopPayload(),
            environment: ["MUXY_SESSION_ID": "42", "MUXY_EYE_SOCKET": url.path],
            home: FileManager.default.temporaryDirectory
        )
        #expect(sent)
        let received = await first(stream)
        let envelope = try #require(received)
        #expect(envelope.event == "Stop")
        #expect(envelope.muxySessionID == MuxySessionID("42"))
        #expect(envelope.payload["last_assistant_message"]?.stringValue == "Done. `spike-ok.txt` created.")
    }

    @Test func noSessionIdIsSkipped() throws {
        let sent = HookForwarder.forward(
            event: "Stop",
            stdin: Data("{}".utf8),
            environment: ["MUXY_EYE_SOCKET": socketURL().path],
            home: FileManager.default.temporaryDirectory
        )
        #expect(!sent)
    }

    @Test func missingSocketFailsFast() {
        let started = Date()
        let sent = HookForwarder.forward(
            event: "Stop",
            stdin: Data("{}".utf8),
            environment: ["MUXY_SESSION_ID": "1", "MUXY_EYE_SOCKET": "/nonexistent/x.sock"],
            home: FileManager.default.temporaryDirectory
        )
        #expect(!sent)
        #expect(Date().timeIntervalSince(started) < 0.3)
    }

    @Test func socketPermissionsAre0600() throws {
        let url = socketURL()
        let server = HookSocketServer(socketURL: url)
        _ = try server.start()
        defer { server.stop() }

        let socketMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(socketMode == 0o600)
        #expect(dirMode == 0o700)
    }

    @Test func serverSkipsMalformedLineAndContinues() async throws {
        let url = socketURL()
        let server = HookSocketServer(socketURL: url)
        let stream = try server.start()
        defer { server.stop() }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(fd >= 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = url.path
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in path.utf8.enumerated() { buffer[index] = byte }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(connected == 0)
        let junk = Array("not json\n".utf8)
        _ = junk.withUnsafeBytes { write(fd, $0.baseAddress, junk.count) }
        close(fd)

        let sent = HookForwarder.forward(
            event: "Stop",
            stdin: try stopPayload(),
            environment: ["MUXY_SESSION_ID": "7", "MUXY_EYE_SOCKET": url.path],
            home: FileManager.default.temporaryDirectory
        )
        #expect(sent)
        let received = await first(stream)
        let envelope = try #require(received)
        #expect(envelope.muxySessionID == MuxySessionID("7"))
    }
}

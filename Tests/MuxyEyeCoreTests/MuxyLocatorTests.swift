import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct MuxyLocatorTests {
    @Test func locatorOrder() {
        let urls = MuxyLocator.candidates(
            home: URL(fileURLWithPath: "/Users/x"),
            override: nil,
            pathVariable: "/opt/bin:/usr/bin"
        )
        #expect(urls.map(\.path) == [
            "/Users/x/.local/bin/muxy",
            "/Applications/Muxy.app/Contents/MacOS/muxy",
            "/Applications/Muxy Beta.app/Contents/MacOS/muxy",
            "/opt/bin/muxy",
            "/usr/bin/muxy"
        ])
    }

    @Test func locatorPrefersOverride() {
        let urls = MuxyLocator.candidates(
            home: URL(fileURLWithPath: "/Users/x"),
            override: "/tmp/m",
            pathVariable: nil
        )
        #expect(urls.first?.path == "/tmp/m")
        #expect(urls.count == 4)
    }

    @Test func locateReturnsFirstExecutable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = dir.appendingPathComponent("muxy")
        try "#!/bin/sh\n".write(to: exe, atomically: true, encoding: .utf8)
        let home = URL(fileURLWithPath: "/nonexistent-home")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: exe.path)
        #expect(MuxyLocator.locate(home: home, override: exe.path, pathVariable: nil)?.path != exe.path)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        #expect(MuxyLocator.locate(home: home, override: exe.path, pathVariable: nil)?.path == exe.path)
        #expect(MuxyLocator.locate(home: home, override: nil, pathVariable: "/nonexistent-bin:\(dir.path)")?.path == exe.path
            || FileManager.default.isExecutableFile(atPath: "/Applications/Muxy.app/Contents/MacOS/muxy"))
    }
}

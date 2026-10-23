import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct HookInstallerTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HookInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func installer(
        _ dir: URL,
        helper: String = "A",
        now: @escaping @Sendable () -> Date = Date.init
    ) -> HookInstaller {
        HookInstaller(
            settingsURL: dir.appendingPathComponent("claude/settings.json"),
            helperURL: dir.appendingPathComponent("\(helper)/bin/muxy-eye-hook"),
            now: now
        )
    }

    private func settingsURL(_ dir: URL) -> URL { dir.appendingPathComponent("claude/settings.json") }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func groups(_ json: [String: Any], _ event: String) -> [[String: Any]] {
        ((json["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }

    private func writeSettings(_ dir: URL, _ text: String) throws {
        try FileManager.default.createDirectory(
            at: settingsURL(dir).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settingsURL(dir))
    }

    private func backups(_ dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: settingsURL(dir).deletingLastPathComponent(), includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("settings.json.muxy-eye-backup-") }
    }

    @Test func installCreatesMissingFile() throws {
        let dir = try makeDir()
        let sut = installer(dir)
        #expect(try sut.status() == .notInstalled)
        try sut.install()
        #expect(try sut.status() == .installed)
        let json = try readJSON(settingsURL(dir))
        let stop = groups(json, "Stop")
        let hook = try #require((stop[0]["hooks"] as? [[String: Any]])?[0])
        let helperPath = dir.appendingPathComponent("A/bin/muxy-eye-hook").path
        #expect(hook["command"] as? String == "\"\(helperPath)\" Stop")
        #expect(hook["type"] as? String == "command")
        #expect(hook["timeout"] as? Int == 5)
        #expect(stop[0]["matcher"] == nil)
        #expect(groups(json, "PreToolUse")[0]["matcher"] as? String == "AskUserQuestion")
        #expect(groups(json, "PermissionRequest")[0]["matcher"] as? String == "*")
        #expect(groups(json, "PostToolUse")[0]["matcher"] as? String == "*")
        #expect(try backups(dir).isEmpty)
    }

    @Test func installPreservesForeignHooks() throws {
        let dir = try makeDir()
        let original = #"{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#
        try writeSettings(dir, original)
        try installer(dir).install()
        let json = try readJSON(settingsURL(dir))
        #expect(json["model"] as? String == "x")
        let stop = groups(json, "Stop")
        #expect(stop.count == 2)
        let first = try #require((stop[0]["hooks"] as? [[String: Any]])?[0])
        #expect(first["command"] as? String == "say hi")
        let found = try backups(dir)
        #expect(found.count == 1)
        #expect(try Data(contentsOf: found[0]) == Data(original.utf8))
    }

    @Test func backupNameUsesInjectedNow() throws {
        let dir = try makeDir()
        try writeSettings(dir, "{}")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try installer(dir, now: { date }).install()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let expected = "settings.json.muxy-eye-backup-\(formatter.string(from: date))"
        #expect(try backups(dir).map(\.lastPathComponent) == [expected])
    }

    @Test func installIsIdempotent() throws {
        let dir = try makeDir()
        let sut = installer(dir)
        try sut.install()
        try sut.install()
        let json = try readJSON(settingsURL(dir))
        for entry in HookInstaller.entries {
            let ours = groups(json, entry.event).filter {
                (($0["hooks"] as? [[String: Any]]) ?? []).contains {
                    ($0["command"] as? String)?.contains("muxy-eye-hook") == true
                }
            }
            #expect(ours.count == 1)
        }
        #expect(try sut.status() == .installed)
    }

    @Test func installRefusesMalformedSettings() throws {
        let dir = try makeDir()
        try writeSettings(dir, "{ not json")
        #expect(throws: HookInstallerError.self) { try installer(dir).install() }
        #expect(try Data(contentsOf: settingsURL(dir)) == Data("{ not json".utf8))
        #expect(try backups(dir).isEmpty)
        try writeSettings(dir, "[1,2]")
        #expect(throws: HookInstallerError.self) { try installer(dir).uninstall() }
    }

    @Test func emptyFileTreatedAsEmptyObject() throws {
        let dir = try makeDir()
        try writeSettings(dir, "  \n")
        let sut = installer(dir)
        #expect(try sut.status() == .notInstalled)
        try sut.install()
        #expect(try sut.status() == .installed)
    }

    @Test func statusNeedsUpdateWhenPathChanged() throws {
        let dir = try makeDir()
        try installer(dir, helper: "A").install()
        #expect(try installer(dir, helper: "B").status() == .needsUpdate)
    }

    @Test func uninstallRemovesOnlyOurs() throws {
        let dir = try makeDir()
        try writeSettings(dir, #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#)
        let sut = installer(dir)
        try sut.install()
        try sut.uninstall()
        let json = try readJSON(settingsURL(dir))
        #expect(groups(json, "Stop").count == 1)
        #expect((json["hooks"] as? [String: Any])?.keys.sorted() == ["Stop"])
        let text = try String(contentsOf: settingsURL(dir), encoding: .utf8)
        #expect(!text.contains("muxy-eye-hook"))
        #expect(try sut.status() == .notInstalled)
    }

    @Test func settingsLocationRespectsConfigDir() {
        let home = URL(fileURLWithPath: "/h", isDirectory: true)
        #expect(ClaudeSettingsLocation.settingsURL(environment: ["CLAUDE_CONFIG_DIR": "/c"], home: home).path == "/c/settings.json")
        #expect(ClaudeSettingsLocation.settingsURL(environment: ["CLAUDE_CONFIG_DIR": "rel"], home: home).path == "/h/.claude/settings.json")
        #expect(ClaudeSettingsLocation.settingsURL(environment: [:], home: home).path == "/h/.claude/settings.json")
    }

    @Test func helperCopiedOnlyWhenChanged() throws {
        let dir = try makeDir()
        let source = dir.appendingPathComponent("src")
        let dest = dir.appendingPathComponent("support/bin/muxy-eye-hook")
        try Data("one".utf8).write(to: source)
        try HookInstaller.installHelper(from: source, to: dest)
        #expect(try Data(contentsOf: dest) == Data("one".utf8))
        func mode(_ url: URL) throws -> Int {
            try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        }
        #expect(try mode(dest) == 0o755)
        #expect(try mode(dest.deletingLastPathComponent()) == 0o700)
        #expect(try mode(dest.deletingLastPathComponent().deletingLastPathComponent()) == 0o700)
        let inode1 = try #require(FileManager.default.attributesOfItem(atPath: dest.path)[.systemFileNumber] as? Int)
        try HookInstaller.installHelper(from: source, to: dest)
        let inode2 = try #require(FileManager.default.attributesOfItem(atPath: dest.path)[.systemFileNumber] as? Int)
        #expect(inode1 == inode2)
        try Data("two".utf8).write(to: source)
        try HookInstaller.installHelper(from: source, to: dest)
        #expect(try Data(contentsOf: dest) == Data("two".utf8))
        #expect(try mode(dest) == 0o755)
    }
}

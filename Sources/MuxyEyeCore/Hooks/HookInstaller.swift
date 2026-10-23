import Foundation

public enum ClaudeSettingsLocation {
    public static func settingsURL(environment: [String: String], home: URL) -> URL {
        if let dir = environment["CLAUDE_CONFIG_DIR"], dir.hasPrefix("/") {
            return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("settings.json")
        }
        return home.appendingPathComponent(".claude/settings.json")
    }
}

public enum HookInstallStatus: Sendable, Equatable {
    case notInstalled, installed, needsUpdate
}

public enum HookInstallerError: Error, Equatable {
    case malformedSettings(String)
}

public struct HookInstaller: Sendable {
    public static let entries: [(event: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("SessionEnd", nil),
        ("UserPromptSubmit", nil),
        ("PermissionRequest", "*"),
        ("PreToolUse", "AskUserQuestion"),
        ("PostToolUse", "*"),
        ("Notification", nil),
        ("Stop", nil)
    ]

    private static let marker = "muxy-eye-hook"

    private let settingsURL: URL
    private let helperURL: URL
    private let now: @Sendable () -> Date

    public init(settingsURL: URL, helperURL: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.settingsURL = settingsURL
        self.helperURL = helperURL
        self.now = now
    }

    public func status() throws -> HookInstallStatus {
        guard let original = try readSettings() else { return .notInstalled }
        let hooks = try hooksDictionary(original.settings)
        var oursTotal = 0
        var current = 0
        for (event, matcher) in Self.entries {
            let ours = Self.ourGroups(hooks[event])
            oursTotal += ours.count
            if ours.count == 1, Self.matches(ours[0], matcher: matcher, command: command(for: event)) {
                current += 1
            }
        }
        let anyOurs = hooks.values.contains { !Self.ourGroups($0).isEmpty }
        if !anyOurs { return .notInstalled }
        return current == Self.entries.count && oursTotal == Self.entries.count ? .installed : .needsUpdate
    }

    public func install() throws {
        let original = try readSettings()
        var settings = original?.settings ?? [:]
        var hooks = try hooksDictionary(settings)
        Self.removeOurs(from: &hooks)
        for (event, matcher) in Self.entries {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command(for: event), "timeout": 5] as [String: Any]]
            ]
            if let matcher { group["matcher"] = matcher }
            var groups = hooks[event] as? [Any] ?? []
            groups.append(group)
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try write(settings, replacing: original)
    }

    public func uninstall() throws {
        guard let original = try readSettings() else { return }
        var settings = original.settings
        var hooks = try hooksDictionary(settings)
        guard hooks.values.contains(where: { !Self.ourGroups($0).isEmpty }) else { return }
        Self.removeOurs(from: &hooks)
        settings["hooks"] = hooks
        try write(settings, replacing: original)
    }

    public static func installHelper(from bundled: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try createDirectories(at: destination.deletingLastPathComponent())
        let data = try Data(contentsOf: bundled)
        if fileManager.fileExists(atPath: destination.path),
           let existing = try? Data(contentsOf: destination), existing == data {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            return
        }
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".muxy-eye-hook-\(UUID().uuidString).tmp")
        try data.write(to: temp)
        do {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
            if rename(temp.path, destination.path) != 0 {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }

    // MARK: - Private

    private struct Original {
        let data: Data
        let settings: [String: Any]
    }

    private func command(for event: String) -> String {
        "\"\(helperURL.path)\" \(event)"
    }

    private func readSettings() throws -> Original? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        let text = String(decoding: data, as: UTF8.self)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Original(data: data, settings: [:])
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HookInstallerError.malformedSettings("not valid JSON")
        }
        guard let object = parsed as? [String: Any] else {
            throw HookInstallerError.malformedSettings("top level is not an object")
        }
        return Original(data: data, settings: object)
    }

    private func hooksDictionary(_ settings: [String: Any]) throws -> [String: Any] {
        guard let value = settings["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw HookInstallerError.malformedSettings("\"hooks\" is not an object")
        }
        for (event, _) in Self.entries {
            if let groups = hooks[event], !(groups is [Any]) {
                throw HookInstallerError.malformedSettings("\"hooks.\(event)\" is not an array")
            }
        }
        return hooks
    }

    private func write(_ settings: [String: Any], replacing original: Original?) throws {
        let fileManager = FileManager.default
        let output = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let directory = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let original {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = directory.appendingPathComponent(
                "\(settingsURL.lastPathComponent).muxy-eye-backup-\(formatter.string(from: now()))"
            )
            try original.data.write(to: backup)
        }
        let target = settingsURL.resolvingSymlinksInPath()
        let mode = (try? fileManager.attributesOfItem(atPath: target.path))?[.posixPermissions] as? Int
        try output.write(to: target, options: .atomic)
        if let mode {
            try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
        }
    }

    private static func isOurs(_ hook: Any) -> Bool {
        guard let dict = hook as? [String: Any], let command = dict["command"] as? String else { return false }
        return command.contains(marker)
    }

    private static func ourGroups(_ value: Any?) -> [[String: Any]] {
        (value as? [Any] ?? []).compactMap { group in
            guard let dict = group as? [String: Any], let inner = dict["hooks"] as? [Any],
                  inner.contains(where: isOurs) else { return nil }
            return dict
        }
    }

    private static func matches(_ group: [String: Any], matcher: String?, command: String) -> Bool {
        guard group["matcher"] as? String == matcher,
              let inner = group["hooks"] as? [Any], inner.count == 1,
              let hook = inner[0] as? [String: Any] else { return false }
        return hook["command"] as? String == command
    }

    private static func removeOurs(from hooks: inout [String: Any]) {
        for (event, value) in hooks {
            guard let groups = value as? [Any], groups.contains(where: { ourGroups([$0]).isEmpty == false }) else { continue }
            var kept: [Any] = []
            for group in groups {
                guard var dict = group as? [String: Any], let inner = dict["hooks"] as? [Any],
                      inner.contains(where: isOurs) else {
                    kept.append(group)
                    continue
                }
                let remaining = inner.filter { !isOurs($0) }
                if remaining.isEmpty { continue }
                dict["hooks"] = remaining
                kept.append(dict)
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
    }

    private static func createDirectories(at url: URL) throws {
        let fileManager = FileManager.default
        var missing: [URL] = []
        var cursor = url
        while !fileManager.fileExists(atPath: cursor.path) {
            missing.append(cursor)
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        for directory in missing.reversed() {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }
}

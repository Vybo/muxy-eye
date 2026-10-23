import Foundation

public enum MuxyLocator {
    public static func candidates(home: URL, override: String?, pathVariable: String?) -> [URL] {
        var result: [URL] = []
        if let override, !override.isEmpty {
            result.append(URL(fileURLWithPath: override))
        }
        result.append(home.appendingPathComponent(".local/bin/muxy"))
        result.append(URL(fileURLWithPath: "/Applications/Muxy.app/Contents/MacOS/muxy"))
        result.append(URL(fileURLWithPath: "/Applications/Muxy Beta.app/Contents/MacOS/muxy"))
        if let pathVariable {
            for entry in pathVariable.split(separator: ":") where !entry.isEmpty {
                result.append(URL(fileURLWithPath: String(entry)).appendingPathComponent("muxy"))
            }
        }
        return result
    }

    public static func locate(home: URL, override: String?, pathVariable: String?) -> URL? {
        let fileManager = FileManager.default
        return candidates(home: home, override: override, pathVariable: pathVariable).first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && fileManager.isExecutableFile(atPath: url.path)
        }
    }
}

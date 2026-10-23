import Foundation

enum Fixture {
    enum FixtureError: Error { case missing(String) }

    static func data(_ path: String) throws -> Data {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures/\(path)"),
              FileManager.default.fileExists(atPath: url.path)
        else { throw FixtureError.missing(path) }
        return try Data(contentsOf: url)
    }

    static func text(_ path: String) throws -> String {
        String(decoding: try data(path), as: UTF8.self)
    }
}

import Foundation
import Testing
@testable import MuxyEyeCore

@Suite struct SetupTextTests {
    private func info(protocols: [Int]) throws -> MuxyBuildInfo {
        let json = #"{"version":"1.4.2","compatibility":1,"protocol":\#(protocols)}"#
        return try JSONDecoder().decode(MuxyBuildInfo.self, from: Data(json.utf8))
    }

    @Test func hookStatusTitles() {
        #expect(SetupText.hookStatusTitle(.notInstalled) == "Not installed")
        #expect(SetupText.hookStatusTitle(.installed) == "Installed")
        #expect(SetupText.hookStatusTitle(.needsUpdate) == "Needs update")
        #expect(SetupText.hookStatusTitle(nil) == "Unknown")
    }

    @Test func installButtonFollowsStatus() {
        #expect(SetupText.installButtonTitle(.notInstalled) == "Install")
        #expect(SetupText.installButtonTitle(.needsUpdate) == "Update")
        #expect(SetupText.installButtonTitle(.installed) == nil)
        #expect(SetupText.installButtonTitle(nil) == "Install")
    }

    @Test func removeIsOfferedOnlyWhenSomethingIsInstalled() {
        #expect(SetupText.canRemoveHooks(.installed))
        #expect(SetupText.canRemoveHooks(.needsUpdate))
        #expect(!SetupText.canRemoveHooks(.notInstalled))
        #expect(!SetupText.canRemoveHooks(nil))
    }

    @Test func muxyLocationText() throws {
        let path = "/Users/a/.local/bin/muxy"
        #expect(SetupText.muxyLocation(path: nil, buildInfo: nil) == "Muxy not found")
        #expect(SetupText.muxyLocation(path: path, buildInfo: nil) == "Muxy found: \(path)")
        #expect(SetupText.muxyLocation(path: path, buildInfo: try info(protocols: [2])) == "Muxy found: \(path) (1.4.2)")
    }

    @Test func unsupportedWarningOnlyForUnsupportedProtocol() throws {
        #expect(SetupText.unsupportedVersionWarning(try info(protocols: [2])) == nil)
        #expect(SetupText.unsupportedVersionWarning(nil) == nil)
        #expect(SetupText.unsupportedVersionWarning(try info(protocols: [1, 3]))
            == "This Muxy version uses an unsupported protocol")
    }

    @Test func installErrorText() {
        #expect(SetupText.hookError(HookInstallerError.malformedSettings("not valid JSON"))
            == "Claude settings were left untouched: not valid JSON")
    }
}

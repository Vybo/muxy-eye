import Foundation
import MuxyEyeCore

HookForwarder.forward(
    event: CommandLine.arguments.dropFirst().first ?? "",
    stdin: (try? FileHandle.standardInput.readToEnd()) ?? Data(),
    environment: ProcessInfo.processInfo.environment,
    home: FileManager.default.homeDirectoryForCurrentUser
)
exit(0)

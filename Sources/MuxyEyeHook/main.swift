import Foundation
import MuxyEyeCore

HookForwarder.forward(
    event: CommandLine.arguments.dropFirst().first ?? "",
    stdin: FileHandle.standardInput.readDataToEndOfFile(),
    environment: ProcessInfo.processInfo.environment,
    home: FileManager.default.homeDirectoryForCurrentUser
)
exit(0)

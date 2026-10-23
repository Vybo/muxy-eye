import Foundation

/// Wording for the onboarding and settings screens.
public enum SetupText {
    public static let restartHint = "Restart running Claude sessions (or review /hooks) to pick up the hooks."

    public static func hookStatusTitle(_ status: HookInstallStatus?) -> String {
        switch status {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .needsUpdate: "Needs update"
        case nil: "Unknown"
        }
    }

    /// The install button's title, or nil when the installed hooks are already current.
    public static func installButtonTitle(_ status: HookInstallStatus?) -> String? {
        switch status {
        case .installed: nil
        case .needsUpdate: "Update"
        case .notInstalled, nil: "Install"
        }
    }

    public static func canRemoveHooks(_ status: HookInstallStatus?) -> Bool {
        status == .installed || status == .needsUpdate
    }

    public static func muxyLocation(path: String?, buildInfo: MuxyBuildInfo?) -> String {
        guard let path else { return "Muxy not found" }
        guard let buildInfo else { return "Muxy found: \(path)" }
        return "Muxy found: \(path) (\(buildInfo.version))"
    }

    public static func unsupportedVersionWarning(_ buildInfo: MuxyBuildInfo?) -> String? {
        guard let buildInfo, !buildInfo.isSupported else { return nil }
        return "This Muxy version uses an unsupported protocol"
    }

    public static func hookError(_ error: Error) -> String {
        if case HookInstallerError.malformedSettings(let reason) = error {
            return "Claude settings were left untouched: \(reason)"
        }
        return error.localizedDescription
    }
}

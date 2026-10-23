import Observation
import ServiceManagement

/// The "Launch at login" registration of the main app.
@MainActor @Observable
final class LaunchAtLogin {
    private(set) var isEnabled: Bool
    private(set) var errorText: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let model: AppModel
    private let launchAtLogin = LaunchAtLogin()
    private var windowController: EyeWindowController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    override init() {
        settings = AppSettings()
        model = AppModel(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = EyeWindowController(model: model, settings: settings)
        model.presenter = controller
        model.openSettings = { [weak self] in self?.showSettings() }
        windowController = controller
        controller.show()
        model.start()
        if !settings.didOnboard {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    // MARK: Windows

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "Muxy Eye Settings",
                content: SettingsView(model: model, settings: settings, launchAtLogin: launchAtLogin)
            )
        }
        bringFront(settingsWindow)
    }

    private func showOnboarding() {
        let view = OnboardingView(model: model, settings: settings, launchAtLogin: launchAtLogin) { [weak self] in
            self?.settings.didOnboard = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        onboardingWindow = makeWindow(title: "Welcome to Muxy Eye", content: view)
        bringFront(onboardingWindow)
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// The app is an agent without a Dock icon, so a window only gets focus when it is brought forward explicitly.
    private func bringFront(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

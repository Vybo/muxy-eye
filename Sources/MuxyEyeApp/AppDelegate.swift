import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        // `open "Muxy Eye.app" --args --settings` opens Settings at launch.
        if CommandLine.arguments.contains("--settings") {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    // MARK: Windows

    /// Onboarding is shown once, however its window is closed.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        settings.didOnboard = true
        onboardingWindow = nil
    }

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
            self?.onboardingWindow?.close()
        }
        onboardingWindow = makeWindow(title: "Welcome to Muxy Eye", content: view)
        onboardingWindow?.delegate = self
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
    /// macOS can decline the activation while another app is in front (from the eye's menu, for example), and
    /// the window would then open behind that app's windows; ordering it front regardless keeps it on top.
    private func bringFront(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

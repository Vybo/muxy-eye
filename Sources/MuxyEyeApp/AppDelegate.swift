import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let model: AppModel
    private var windowController: EyeWindowController?

    override init() {
        settings = AppSettings()
        model = AppModel(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = EyeWindowController(model: model, settings: settings)
        model.presenter = controller
        windowController = controller
        controller.show()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

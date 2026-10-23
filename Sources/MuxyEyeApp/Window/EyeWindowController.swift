import AppKit
import MuxyEyeCore
import Observation
import SwiftUI

/// Owns the eye's panel: sizes it to the collapsed shape or the expanded frame on the target screen.
@MainActor
final class EyeWindowController: EyePresenting {
    /// Used until the expanded panel has measured its content.
    private static let initialExpandedHeight: CGFloat = 220

    private let model: AppModel
    private let settings: AppSettings
    private let panel = EyePanel()
    private let hostingView: EyeHostingView
    private let events = PanelEventMonitor()
    private var expandedHeight = initialExpandedHeight
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        hostingView = EyeHostingView(rootView: EyeRootView(model: model, content: nil, onExpandedHeight: { _ in }))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    func show() {
        observeNotifications()
        observeModel()
        updateFrame()
        panel.orderFrontRegardless()
    }

    // MARK: EyePresenting

    func present(expanded: Bool, focus: Bool) {
        let wasKey = panel.isKeyWindow
        panel.isExpanded = expanded
        updateFrame()
        if expanded {
            startEventMonitor()
            panel.orderFrontRegardless()
            if focus { panel.makeKey() }
        } else {
            events.stop()
            if wasKey {
                // Hand the keyboard back to the app the user was in.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
    }

    // MARK: Layout

    private func updateFrame() {
        guard let screen = targetScreen() else { return }
        let geometry = ScreenGeometry(screen)
        let frame: CGRect
        let content: EyeRootView.Content
        if model.expanded {
            let topInset = geometry.hasNotch ? geometry.safeAreaTop : 0
            frame = EyeLayout.expandedFrame(on: geometry, contentHeight: max(expandedHeight, topInset))
            content = .expanded(topInset: topInset)
        } else {
            let collapsed = EyeLayout.collapsed(on: geometry, waitingCount: model.state.waitingCount)
            frame = collapsed.panelFrame
            content = .collapsed(collapsed)
        }
        if hostingView.rootView.content != content {
            hostingView.rootView = EyeRootView(model: model, content: content) { [weak self] height in
                self?.expandedHeightChanged(height)
            }
        }
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    /// The expanded panel reports its height from inside a SwiftUI update, so the resize waits a turn.
    private func expandedHeightChanged(_ height: CGFloat) {
        guard abs(height - expandedHeight) >= 1 else { return }
        expandedHeight = height
        Task { @MainActor [weak self] in
            guard let self, self.model.expanded else { return }
            self.updateFrame()
        }
    }

    private func targetScreen() -> NSScreen? {
        if let pinned = settings.pinnedDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == pinned }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func startEventMonitor() {
        events.start(
            panel: panel,
            onClickOutside: { [weak self] in self?.model.collapse() },
            onKey: { [weak self] key in self?.model.handleKey(key) }
        )
    }

    // MARK: Observation

    private func observeModel() {
        withObservationTracking {
            _ = model.expanded
            _ = model.state.waitingCount
            _ = settings.pinnedDisplayID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateFrame()
                self?.observeModel()
            }
        }
    }

    private func observeNotifications() {
        let relayout: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrame() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.panelBecameKey() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
            using: relayout
        ))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main,
            using: relayout
        ))
    }
}

// MARK: - Hosting

/// Takes the first click even though the panel is not key, so one click on the eye expands it.
final class EyeHostingView: NSHostingView<EyeRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Screen geometry

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

extension ScreenGeometry {
    init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}

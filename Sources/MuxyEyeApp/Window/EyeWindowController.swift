import AppKit
import MuxyEyeCore
import Observation
import SwiftUI

/// Owns the eye's panel: sizes it to the collapsed shape or the expanded frame on the target screen.
@MainActor
final class EyeWindowController: EyePresenting {
    private static let expandedContentHeight: CGFloat = 200

    private let model: AppModel
    private let settings: AppSettings
    private let panel = EyePanel()
    private let hostingView: EyeHostingView
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        hostingView = EyeHostingView(rootView: EyeRootView(model: model, layout: nil))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    func show() {
        observeScreens()
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
            panel.orderFrontRegardless()
            if focus { panel.makeKey() }
        } else if wasKey {
            // Hand the keyboard back to the app the user was in.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    // MARK: Layout

    private func updateFrame() {
        guard let screen = targetScreen() else { return }
        let geometry = ScreenGeometry(screen)
        let frame: CGRect
        let layout: CollapsedLayout?
        if model.expanded {
            frame = EyeLayout.expandedFrame(on: geometry, contentHeight: Self.expandedContentHeight)
            layout = nil
        } else {
            let collapsed = EyeLayout.collapsed(on: geometry, waitingCount: model.state.waitingCount)
            frame = collapsed.panelFrame
            layout = collapsed
        }
        if hostingView.rootView.layout != layout {
            hostingView.rootView = EyeRootView(model: model, layout: layout)
        }
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func targetScreen() -> NSScreen? {
        if let pinned = settings.pinnedDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == pinned }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
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

    private func observeScreens() {
        let relayout: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrame() }
        }
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

struct EyeRootView: View {
    let model: AppModel
    let layout: CollapsedLayout?

    var body: some View {
        Group {
            if model.expanded {
                ExpandedPlaceholderView(model: model)
            } else if let layout {
                CollapsedEyeView(model: model, layout: layout)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// Stands in for the expanded panel until the sessions rail and prompt views exist.
private struct ExpandedPlaceholderView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            SignalLineEyeView(mode: model.state.mode)
                .frame(width: 28, height: 28)
            Text(summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelTheme.text)
            Text("Click to collapse")
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.secondaryText)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22, style: .continuous)
                .fill(PanelTheme.background)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.collapse() }
    }

    private var summary: String {
        let state = model.state
        guard state.muxyRunning else { return "Muxy is not running" }
        let waiting = state.waitingCount
        if waiting > 0 { return waiting == 1 ? "1 session needs you" : "\(waiting) sessions need you" }
        let working = state.sessions.values.filter { $0.muxyState == .working }.count
        return working > 0 ? "\(working) working" : "All agents idle"
    }
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

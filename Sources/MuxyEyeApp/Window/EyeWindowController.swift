import AppKit
import MuxyEyeCore
import Observation
import SwiftUI

/// Owns the eye's panel. The SwiftUI view draws on a stage that covers everything the eye can show on
/// the target screen; the window shows only the visible part of it. At rest that is the collapsed eye
/// or the expanded panel, so clicks around them pass through. While the eye morphs into the panel or
/// back, the window first grows to cover both, the shape animates inside it, and only once the
/// animation is done does the window shrink to what's left.
@MainActor
final class EyeWindowController: EyePresenting {
    /// Used until the expanded panel has measured its content.
    private static let initialExpandedHeight: CGFloat = 220

    private let model: AppModel
    private let settings: AppSettings
    private let panel = EyePanel()
    private let stage: EyeStage
    private let hostingView: EyeHostingView
    private let events = PanelEventMonitor()
    private var expandedHeight = initialExpandedHeight
    private var observers: [NSObjectProtocol] = []
    private var hiddenTask: Task<Void, Never>?

    private var geometry: ScreenGeometry?
    /// The waiting count the eye shows, to notice when its badge pops.
    private var waitingCount = 0
    /// Room around moving shapes for a spring's overshoot, on the current screen.
    private var margin: CGFloat = 0
    private var window = EyeWindowFrame(footprint: .zero)
    private var settleTask: Task<Void, Never>?
    /// Pulls the panel's shape back into the eye once the content has faded.
    private var pullBackTask: Task<Void, Never>?

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        let stage = EyeStage()
        self.stage = stage
        hostingView = EyeHostingView(rootView: EyeRootView(model: model, stage: stage, onExpandedHeight: { _ in }))
        hostingView.sizingOptions = []
        panel.contentView = EyeStageView(hostingView: hostingView)
        hostingView.rootView = EyeRootView(model: model, stage: stage) { [weak self] height in
            self?.expandedHeightChanged(height)
        }
    }

    func show() {
        observeNotifications()
        observeModel()
        updateFrame()
        panel.orderFrontRegardless()
    }

    /// Orders the panel out and brings it back after `duration`. The model keeps polling meanwhile.
    func hide(for duration: Duration) {
        hiddenTask?.cancel()
        events.stop()
        panel.orderOut(nil)
        hiddenTask = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.hiddenTask = nil
            guard let self else { return }
            self.updateFrame()
            self.panel.orderFrontRegardless()
            // Restores the event monitor when auto-expand opened the panel while it was hidden.
            self.present(expanded: self.model.expanded, focus: false)
        }
    }

    // MARK: EyePresenting

    func present(expanded: Bool, focus: Bool) {
        let wasKey = panel.isKeyWindow
        panel.isExpanded = expanded
        updateFrame()
        if hiddenTask != nil { return }
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

    /// Moves the stage to the model's state: opens or closes the panel, follows the waiting count and
    /// the content's height. Everything jumps instead of animating while the panel isn't on screen
    /// or when it moves to another screen.
    private func updateFrame() {
        guard let screen = targetScreen() else { return }
        let geometry = ScreenGeometry(screen)
        let collapsed = EyeLayout.collapsed(on: geometry, waitingCount: model.state.waitingCount)
        let topInset = geometry.hasNotch ? geometry.safeAreaTop : 0
        let expanded = EyeLayout.expandedFrame(on: geometry, contentHeight: max(expandedHeight, topInset))
        let phase = stage.phase.requesting(expanded: model.expanded)

        guard geometry == self.geometry, hiddenTask == nil, panel.isVisible else {
            self.geometry = geometry
            jump(to: phase.settled, collapsed: collapsed, expanded: expanded, topInset: topInset, on: geometry)
            return
        }

        let motion = PanelMotion(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let previous = stage.phase
        let collapsedChanged = stage.collapsed != collapsed
        let expandedChanged = stage.expandedFrame != expanded
        let countChanged = model.state.waitingCount != waitingCount
        waitingCount = model.state.waitingCount
        stage.topInset = topInset
        stage.expandedFrame = expanded

        var duration: Double?
        func extend(_ seconds: Double?) {
            guard let seconds else { return }
            duration = max(duration ?? 0, seconds)
        }

        // The eye's wing or badge grows or retracts while the eye shows; under the open panel it jumps.
        let eyeShows = phase != .expanded
        if collapsedChanged {
            stage.collapsedMotion = eyeShows ? motion.collapsedChange?.animation : nil
            stage.collapsed = collapsed
            // With Reduce Motion the shape jumps and only the badge fades.
            if eyeShows { extend(motion.collapsedChange?.totalTime ?? motion.transitionFade?.totalTime) }
        }
        // The count's pop needs the window's margin around the badge.
        if countChanged, eyeShows { extend(motion.countPop?.totalTime) }

        if phase != previous {
            stage.phase = phase
            panel.showsShadow = false
            pullBackTask?.cancel()
            pullBackTask = nil
            // With Reduce Motion the shape takes its frame at once and the panel fades instead.
            if phase == .opening {
                stage.panelOpacityMotion = motion.panelFade?.animation
                stage.panelOpacity = 1
                setPanelOutline(EyeLayout.expandedOutline(expanded), motion: motion.shapeOpen)
                extend(motion.openDuration)
            } else {
                if let fade = motion.panelFade {
                    stage.panelOpacityMotion = fade.animation
                    stage.panelOpacity = 0
                }
                schedulePullBack(motion.shapeClose)
                extend(motion.closeDuration)
            }
        } else if expandedChanged, phase.isExpanding {
            // The content measured a new height: follow it, smoothly while still opening.
            let open = phase == .opening ? motion.shapeOpen : nil
            setPanelOutline(EyeLayout.expandedOutline(expanded), motion: open)
            extend(open?.totalTime)
        } else if collapsedChanged, phase == .collapsed {
            // The hidden panel shape stays on the eye's, ready for the next opening.
            setPanelOutline(EyeLayout.collapsedOutline(collapsed), motion: motion.collapsedChange)
        } else if collapsedChanged, phase == .closing, pullBackTask == nil, let shape = motion.shapeClose {
            // Already pulling back: land on the eye's new shape.
            let landing = Motion(shape.curve)
            setPanelOutline(EyeLayout.collapsedOutline(collapsed), motion: landing)
            extend(landing.totalTime)
        }

        let footprint = phase.footprint(collapsed: collapsed, expanded: expanded)
        if let duration {
            window.animate(to: footprint, at: .now, for: .seconds(duration))
        } else {
            window.jump(to: footprint)
        }
        applyWindowFrame()
        scheduleSettle()
    }

    /// Puts everything in place at once, for `phase` at rest.
    private func jump(
        to phase: PanelPhase,
        collapsed: CollapsedLayout,
        expanded: CGRect,
        topInset: CGFloat,
        on geometry: ScreenGeometry
    ) {
        settleTask?.cancel()
        settleTask = nil
        pullBackTask?.cancel()
        pullBackTask = nil
        margin = EyeLayout.motionMargin(on: geometry)
        waitingCount = model.state.waitingCount
        stage.collapsedMotion = nil
        stage.panelMotion = nil
        stage.panelOpacityMotion = nil
        stage.frame = EyeLayout.stageFrame(on: geometry)
        stage.phase = phase
        stage.collapsed = collapsed
        stage.expandedFrame = expanded
        stage.topInset = topInset
        stage.panelOutline = phase == .expanded
            ? EyeLayout.expandedOutline(expanded)
            : EyeLayout.collapsedOutline(collapsed)
        stage.panelOpacity = phase == .expanded ? 1 : 0
        window = EyeWindowFrame(footprint: phase.footprint(collapsed: collapsed, expanded: expanded))
        panel.showsShadow = phase == .expanded
        applyWindowFrame()
    }

    private func setPanelOutline(_ outline: EyeOutline, motion: Motion?) {
        stage.panelMotion = motion?.animation
        stage.panelOutline = outline
    }

    /// The content fades first; after the shape's delay it pulls back into the eye.
    private func schedulePullBack(_ shape: Motion?) {
        guard let shape else { return }
        pullBackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(shape.delay)) } catch { return }
            self?.pullBack(Motion(shape.curve))
        }
    }

    private func pullBack(_ motion: Motion) {
        pullBackTask = nil
        guard stage.phase == .closing else { return }
        setPanelOutline(EyeLayout.collapsedOutline(stage.collapsed), motion: motion)
        window.animate(to: window.footprint, at: .now, for: .seconds(motion.totalTime))
        scheduleSettle()
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = nil
        guard let end = window.settlesAt else { return }
        settleTask = Task { [weak self] in
            do { try await Task.sleep(until: end, clock: .continuous) } catch { return }
            self?.settle()
        }
    }

    /// Every animation is done: the transition ends and the window shrinks to what is visible.
    private func settle() {
        settleTask = nil
        guard window.settle(at: .now) else {
            scheduleSettle()
            return
        }
        let phase = stage.phase.settled
        if phase != stage.phase {
            stage.phase = phase
            if phase == .collapsed {
                // The panel's shape is on the eye's now; hide it there for the next opening.
                setPanelOutline(EyeLayout.collapsedOutline(stage.collapsed), motion: nil)
                stage.panelOpacityMotion = nil
                stage.panelOpacity = 0
            }
        }
        panel.showsShadow = phase == .expanded
        applyWindowFrame()
    }

    /// Sizes the window and puts the stage where the window shows its visible part. Screen updates
    /// wait for both, so the shapes don't jump for a frame while the window moves under them.
    private func applyWindowFrame() {
        let stageFrame = stage.frame
        let frame = window.frame(margin: margin, within: stageFrame)
        let placement = CGRect(
            x: stageFrame.minX - frame.minX,
            y: frame.maxY - stageFrame.maxY,
            width: stageFrame.width,
            height: stageFrame.height
        )
        guard panel.frame != frame || hostingView.frame != placement else { return }
        panel.disableScreenUpdatesUntilFlush()
        hostingView.frame = placement
        panel.setFrame(frame, display: true)
        if panel.showsShadow { panel.invalidateShadow() }
    }

    /// The expanded panel reports its height from inside a SwiftUI update, so the resize waits a turn.
    private func expandedHeightChanged(_ height: CGFloat) {
        guard abs(height - expandedHeight) >= 1 else { return }
        expandedHeight = height
        Task { @MainActor [weak self] in
            guard let self, self.stage.phase.isExpanding else { return }
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

/// The panel's content view. It holds the stage, which is larger than the window, at the offset that
/// puts the visible part in the window. Its origin is at the top left, so the stage stays in place
/// on screen while the window grows or shrinks below and beside it.
final class EyeStageView: NSView {
    init(hostingView: NSView) {
        super.init(frame: .zero)
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// Clicks that miss the stage's shapes don't stop at this view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self ? nil : view
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

import AppKit
import MuxyEyeCore
import Observation
import SwiftUI

/// Owns the eye's panel. The SwiftUI view draws on a stage that covers everything the eye can show on
/// the target screen; the window shows only the visible part of it. At rest that is the collapsed eye
/// or the expanded panel, so clicks around them pass through. While the eye morphs into the panel or
/// back, the window first grows to cover both, the shape animates inside it, and only once the
/// animation is done does the window shrink to what's left.
///
/// The collapsed eye can be dragged somewhere else and resized by scrolling over it; the panel then
/// opens on the side of the eye chosen in Settings.
@MainActor
final class EyeWindowController: EyePresenting {
    /// Used until the expanded panel has measured its content.
    private static let initialExpandedHeight: CGFloat = 220

    /// What the stage is laid out for: the screen, the eye's place and size, and the panel's side.
    private struct Arrangement: Equatable {
        var geometry: ScreenGeometry
        var placement: EyePlacement
        var side: PanelSide
    }

    private let model: AppModel
    private let settings: AppSettings
    private let panel = EyePanel()
    private let stage: EyeStage
    private let hostingView: EyeHostingView
    private let events = PanelEventMonitor()
    private var expandedHeight = initialExpandedHeight
    private var observers: [NSObjectProtocol] = []
    private var hiddenTask: Task<Void, Never>?

    /// The screen the stage is on.
    private var geometry: ScreenGeometry?
    /// What the stage is laid out for; nil while a dragged eye has moved it without laying it out again.
    private var arrangement: Arrangement?
    /// The side the panel opens on. It is chosen while the eye rests and kept until the panel has
    /// closed, so the panel doesn't jump to the other side when its content grows.
    private var openSide = PanelSide.below
    /// A left press on the collapsed eye: a click until the pointer moves, then a drag.
    private var press: EyeDrag?
    /// Where a dragged eye is now; it is saved once the eye is dropped.
    private var draggedPlacement: EyePlacement?
    /// Whether the window at rest last had room for clicks to pass, for the frame and shapes it had.
    private var clickThrough: ClickThroughCheck?
    /// The waiting count the eye shows, to notice when its badge pops.
    private var waitingCount = 0
    /// Room around the panel's shape for its spring's overshoot while it opens or closes, on the
    /// current screen. The eye's own changes need only `PanelMotion.eyeMargin`.
    private var shapeMargin: CGFloat = 0
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
        // While the window is larger than the panel, a click beside it lands here, not in another app.
        panel.onClickOutside = { [weak self] in self?.model.collapse() }
        panel.onEyePointer = { [weak self] pointer in self?.eyePointer(pointer) }
        panel.onEyeScroll = { [weak self] event in self?.eyeScrolled(event) }
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
        panel.clickThroughOutlines = nil
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
        if expanded { endPress() }
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
    /// the content's height. Everything jumps instead of animating while the panel isn't on screen,
    /// when it moves to another screen, and when the eye is moved or resized or the panel's side changes.
    private func updateFrame() {
        guard let screen = targetScreen() else { return }
        let geometry = ScreenGeometry(screen)
        let placement = draggedPlacement ?? settings.eyePlacement
        let arrangement = Arrangement(geometry: geometry, placement: placement, side: settings.panelSide)
        let collapsed = EyeLayout.collapsed(on: geometry, waitingCount: model.state.waitingCount, placement: placement)
        if stage.phase == .collapsed || arrangement != self.arrangement {
            openSide = EyeLayout.openingSide(
                arrangement.side,
                on: geometry,
                collapsed: collapsed,
                placement: placement,
                contentHeight: expandedHeight)
        }
        let topInset = EyeLayout.topInset(on: geometry, collapsed: collapsed, placement: placement, side: openSide)
        let expanded = EyeLayout.expandedFrame(
            on: geometry,
            contentHeight: max(expandedHeight, topInset),
            collapsed: collapsed,
            placement: placement,
            side: openSide)
        let phase = stage.phase.requesting(expanded: model.expanded)

        guard arrangement == self.arrangement, hiddenTask == nil, panel.isVisible else {
            self.geometry = geometry
            self.arrangement = arrangement
            jump(to: phase.settled, collapsed: collapsed, expanded: expanded, topInset: topInset, for: arrangement)
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
        stage.eyeCovered = EyeLayout.panel(expanded, covers: collapsed)
        stage.eyeReturnsEarly = placement.isCustomized

        var duration: Double?
        var margin: CGFloat = 0
        /// An animation starts for `seconds` and may reach `room` beyond what it moves across.
        func extend(_ seconds: Double?, room: CGFloat) {
            guard let seconds else { return }
            duration = max(duration ?? 0, seconds)
            margin = max(margin, room)
        }
        let eyeRoom = PanelMotion.eyeMargin

        // The eye's wing or badge grows or retracts while the eye shows; under the open panel it jumps.
        let eyeShows = phase != .expanded || !stage.eyeCovered
        if collapsedChanged {
            stage.collapsedMotion = eyeShows ? motion.collapsedChange?.animation : nil
            stage.collapsed = collapsed
            // With Reduce Motion the shape jumps and only the badge fades.
            if eyeShows { extend(motion.collapsedChange?.totalTime ?? motion.transitionFade?.totalTime, room: eyeRoom) }
        }
        // The count's pop needs a few points around the badge.
        if countChanged, eyeShows { extend(motion.countPop?.totalTime, room: eyeRoom) }

        if phase != previous {
            stage.phase = phase
            panel.showsShadow = false
            pullBackTask?.cancel()
            pullBackTask = nil
            // With Reduce Motion the shape takes its frame at once and the panel fades instead.
            if phase == .opening {
                stage.reopening = previous == .closing
                stage.panelOpacityMotion = motion.panelFade?.animation
                stage.panelOpacity = 1
                setPanelOutline(EyeLayout.expandedOutline(expanded, on: geometry), motion: motion.shapeOpen)
                extend(motion.openDuration, room: motion.shapeOpen == nil ? 0 : shapeMargin)
            } else {
                if let fade = motion.panelFade {
                    stage.panelOpacityMotion = fade.animation
                    stage.panelOpacity = 0
                }
                schedulePullBack(motion.shapeClose)
                extend(motion.closeDuration, room: motion.shapeClose == nil ? 0 : shapeMargin)
            }
        } else if expandedChanged, phase.isExpanding {
            // The content measured a new height: follow it, smoothly while still opening.
            let open = phase == .opening ? motion.shapeOpen : nil
            setPanelOutline(EyeLayout.expandedOutline(expanded, on: geometry), motion: open)
            extend(open?.totalTime, room: shapeMargin)
        } else if collapsedChanged, phase == .collapsed {
            // The hidden panel shape stays on the eye's, ready for the next opening.
            setPanelOutline(EyeLayout.collapsedOutline(collapsed), motion: motion.collapsedChange)
        } else if collapsedChanged, phase == .closing, pullBackTask == nil, let shape = motion.shapeClose {
            // Already pulling back: land on the eye's new shape.
            let landing = Motion(shape.curve)
            setPanelOutline(EyeLayout.collapsedOutline(collapsed), motion: landing)
            extend(landing.totalTime, room: shapeMargin)
        }

        let footprint = phase.footprint(collapsed: collapsed, expanded: expanded)
        if let duration {
            window.animate(to: footprint, at: .now, for: .seconds(duration), margin: margin)
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
        for arrangement: Arrangement
    ) {
        let geometry = arrangement.geometry
        settleTask?.cancel()
        settleTask = nil
        pullBackTask?.cancel()
        pullBackTask = nil
        shapeMargin = EyeLayout.motionMargin(on: geometry, placement: arrangement.placement, side: arrangement.side)
        waitingCount = model.state.waitingCount
        stage.collapsedMotion = nil
        stage.panelMotion = nil
        stage.panelOpacityMotion = nil
        stage.frame = EyeLayout.stageFrame(on: geometry, placement: arrangement.placement, side: arrangement.side)
        stage.phase = phase
        stage.reopening = false
        stage.collapsed = collapsed
        stage.expandedFrame = expanded
        stage.topInset = topInset
        stage.eyeCovered = EyeLayout.panel(expanded, covers: collapsed)
        stage.eyeReturnsEarly = arrangement.placement.isCustomized
        stage.panelOutline = phase == .expanded
            ? EyeLayout.expandedOutline(expanded, on: geometry)
            : EyeLayout.collapsedOutline(collapsed)
        panel.panelOutline = stage.panelOutline
        stage.panelOpacity = phase == .expanded ? 1 : 0
        window = EyeWindowFrame(footprint: phase.footprint(collapsed: collapsed, expanded: expanded))
        panel.showsShadow = phase == .expanded
        applyWindowFrame()
    }

    /// Moves the panel's shape. The panel takes clicks inside where it is heading.
    private func setPanelOutline(_ outline: EyeOutline, motion: Motion?) {
        stage.panelMotion = motion?.animation
        stage.panelOutline = outline
        panel.panelOutline = outline
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
        window.animate(to: window.footprint, at: .now, for: .seconds(motion.totalTime), margin: shapeMargin)
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
        // Only the eye at rest collapsed can be grabbed; under or within the panel it is the panel's.
        panel.eyeHandles = stage.phase == .collapsed ? EyeLayout.grabOutlines(stage.collapsed) : []
        let stageFrame = stage.frame
        let frame = window.frame(within: stageFrame)
        updateClickThrough(in: frame)
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

    /// At rest, room in the window beside its shapes lets clicks through to what is below. While
    /// shapes move, and while the eye is hidden, the window takes every click, as it always did.
    private func updateClickThrough(in frame: CGRect) {
        let resting = stage.phase == .collapsed || stage.phase == .expanded
        guard resting, !window.isMoving, hiddenTask == nil else {
            panel.clickThroughOutlines = nil
            return
        }
        let outlines = EyeLayout.clickOutlines(stage.collapsed, expanded: stage.phase == .expanded ? stage.expandedFrame : nil)
        let check = clickThrough.flatMap { $0.frame == frame && $0.outlines == outlines ? $0 : nil }
            ?? ClickThroughCheck(frame: frame, outlines: outlines, hasGap: ClickThrough.hasGap(in: frame, around: outlines))
        clickThrough = check
        panel.clickThroughOutlines = check.hasGap ? outlines : nil
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

    // MARK: Moving and resizing

    /// A press on the collapsed eye opens the panel when it comes up without having moved, and drags
    /// the eye once it moves; a dragged eye stays where it is dropped and the panel stays closed.
    private func eyePointer(_ pointer: EyePointer) {
        switch pointer {
        case .down(let point):
            // A press whose release never arrived ends here; an eye it dragged stays where it is.
            endPress()
            guard stage.phase == .collapsed, !model.expanded else { return }
            press = EyeDrag(start: point, eyeCenter: EyeLayout.grabCenter(of: stage.collapsed, pressedAt: point))
        case .dragged(let point):
            guard var press, let center = press.move(to: point) else { return }
            self.press = press
            moveEye(to: center)
        case .up(let point):
            guard let press else { return }
            self.press = nil
            switch press.release(at: point) {
            case .click:
                model.expand(focus: true)
            case .drop(let center):
                moveEye(to: center)
                dropEye()
            }
        }
    }

    /// Puts the eye's centre at `center` while it is dragged. When only its place changes, the stage
    /// and the window move with it, so nothing is drawn again; the stage is laid out anew once the
    /// eye is dropped.
    private func moveEye(to center: CGPoint) {
        guard let geometry else { return }
        let scale = (draggedPlacement ?? settings.eyePlacement).scale
        let placement = EyePlacement(position: EyeLayout.position(of: center, on: geometry), scale: scale)
        draggedPlacement = placement
        let collapsed = EyeLayout.collapsed(on: geometry, waitingCount: model.state.waitingCount, placement: placement)
        guard stage.phase == .collapsed, !window.isMoving, collapsed.isSameShape(as: stage.collapsed) else {
            // Its shape changes (the notch's wings become a circle, the count changes sides): lay it out.
            updateFrame()
            return
        }
        let dx = collapsed.panelFrame.minX - stage.collapsed.panelFrame.minX
        let dy = collapsed.panelFrame.minY - stage.collapsed.panelFrame.minY
        arrangement = nil
        stage.collapsedMotion = nil
        stage.frame = stage.frame.offsetBy(dx: dx, dy: dy)
        stage.expandedFrame = stage.expandedFrame.offsetBy(dx: dx, dy: dy)
        stage.collapsed = collapsed
        setPanelOutline(EyeLayout.collapsedOutline(collapsed), motion: nil)
        window = EyeWindowFrame(footprint: collapsed.panelFrame)
        applyWindowFrame()
    }

    /// Saves where the dragged eye ended up, kept on the screen and out of the notch, rather than
    /// where the pointer let go of it.
    private func dropEye() {
        guard let placement = draggedPlacement else { return }
        draggedPlacement = nil
        if let geometry {
            let dropped = EyeLayout.eyeCenter(of: EyeLayout.collapsed(on: geometry, waitingCount: 0, placement: placement))
            settings.eyePlacement = EyePlacement(position: EyeLayout.position(of: dropped, on: geometry), scale: placement.scale)
        }
        updateFrame()
    }

    /// The panel opens on its own while the eye is pressed, or a press's release never arrived: the
    /// press ends there, and a dragged eye stays where it got to.
    private func endPress() {
        press = nil
        if draggedPlacement != nil { dropEye() }
    }

    /// Scrolling over the collapsed eye resizes it around its centre; from the notch's wings, or beside
    /// the menu-bar eye, the circle it becomes comes under the pointer. Only the fingers' own movement
    /// counts; momentum after they lift would keep resizing it.
    private func eyeScrolled(_ event: NSEvent) {
        if press != nil, NSEvent.pressedMouseButtons & 1 == 0 { endPress() }
        guard press == nil, let geometry, stage.phase == .collapsed, !model.expanded, event.momentumPhase.isEmpty else {
            return
        }
        let current = settings.eyePlacement
        let anchored = EyeLayout.anchoredForResize(
            current, layout: stage.collapsed, pointer: NSEvent.mouseLocation, on: geometry)
        let resized = anchored.resized(
            byScroll: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas,
            inverted: event.isDirectionInvertedFromDevice)
        guard resized.scale != current.scale else { return }
        settings.eyePlacement = resized
        updateFrame()
    }

    // MARK: Observation

    private func observeModel() {
        withObservationTracking {
            _ = model.expanded
            _ = model.state.waitingCount
            _ = settings.pinnedDisplayID
            _ = settings.eyePlacement
            _ = settings.panelSide
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

    /// Returns no view where the stage has nothing to hit. The window still receives such a click:
    /// it doesn't pass through to the menu bar or the app below. That is why the window is larger
    /// than the eye or the panel only while they animate, and why `EyePanel` handles a click beside
    /// the expanded panel itself.
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

/// Whether the window at rest had room for clicks to pass, for one frame and set of shapes, so the
/// window doesn't look for it again while neither changes.
private struct ClickThroughCheck {
    let frame: CGRect
    let outlines: [EyeOutline]
    let hasGap: Bool
}

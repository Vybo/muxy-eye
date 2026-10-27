import AppKit
import MuxyEyeCore

/// A press on the collapsed eye and what follows it, in screen coordinates.
enum EyePointer {
    case down(CGPoint)
    case dragged(CGPoint)
    case up(CGPoint)
}

/// A borderless, non-activating panel above the menu bar that hosts the eye.
final class EyePanel: NSPanel {
    /// Expanded or expanding: a click in it gives it the keyboard.
    var isExpanded = false

    /// While set, the panel can't become key, so the keyboard it hands back (see
    /// `KeyboardHandbackPanel`) doesn't come straight back to it.
    var refusesKey = false

    /// Where the panel's shape is, or is heading, on screen.
    var panelOutline: EyeOutline?

    /// What a press can grab the collapsed eye by, on screen; empty unless the eye is at rest collapsed.
    var eyeHandles: [EyeOutline] = []

    /// A left press on the eye's handles, then its drags and its release. They come here rather than
    /// to the content, so a click can be told from a drag before anything happens, and a drag never
    /// reaches the eye's tap. The window moves with a dragged eye, so the points are taken from the
    /// pointer on screen, not from the window.
    var onEyePointer: ((EyePointer) -> Void)?

    /// Scrolling over the collapsed eye, which resizes it.
    var onEyeScroll: ((NSEvent) -> Void)?

    /// The shapes that take clicks while the window rests with room around them that must let clicks
    /// through to what is below (see `ClickThrough`); nil when the window is all shape, and while
    /// things move, when the window takes every click as it always did.
    var clickThroughOutlines: [EyeOutline]? {
        didSet {
            guard clickThroughOutlines != oldValue else { return }
            clickThroughChanged()
        }
    }

    /// The left button went down on the eye and hasn't come up yet.
    private var pressesEye = false
    /// The left button went down in this window, on the eye or the panel, and hasn't come up yet.
    private var pressedHere = false
    /// While clicks may pass through, these follow the pointer: a global monitor for the events that
    /// go to other apps, a local one with a tracking area for those over this window.
    private var pointerMonitors: [Any] = []
    private var pointerTracking: NSTrackingArea?

    /// Called for a click in the window but outside the expanded panel's outline: in the window's margin
    /// while the panel animates, or at rest in the transparent rounded bottom corners. Clicks outside
    /// the window go to other apps, where the click-outside monitor sees them.
    var onClickOutside: (() -> Void)?

    /// The window's drop shadow, only for the expanded panel at rest: the window server computes it
    /// from the window's shape, which it can't follow while the panel's shape animates inside.
    var showsShadow = false {
        didSet {
            guard showsShadow != oldValue else { return }
            hasShadow = showsShadow
            invalidateShadow()
        }
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool { !refusesKey }
    override var canBecomeMain: Bool { false }

    /// A click in the expanded panel gives it the keyboard, also when it expanded on its own. A click
    /// beside the panel (in the window's margin while it animates) neither takes the keyboard nor
    /// reaches the content: it counts as a click outside.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { pressedHere = true }
        defer {
            if event.type == .leftMouseUp {
                pressedHere = false
                followPointer()
            }
        }
        if takesEyeEvent(event) { return }
        if isExpanded, event.type == .leftMouseDown {
            let point = convertPoint(toScreen: event.locationInWindow)
            guard panelOutline?.contains(point) ?? true else {
                onClickOutside?()
                return
            }
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }

    /// Takes the collapsed eye's presses, drags and scrolls. A control-click goes on to the content,
    /// which opens the eye's menu.
    private func takesEyeEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            // A press whose release was never seen must not hold on to the next one.
            pressesEye = false
            guard !isExpanded, !event.modifierFlags.contains(.control) else { return false }
            let point = convertPoint(toScreen: event.locationInWindow)
            guard eyeHandles.contains(where: { $0.contains(point) }) else { return false }
            pressesEye = true
            onEyePointer?(.down(NSEvent.mouseLocation))
            return true
        case .leftMouseDragged where pressesEye:
            onEyePointer?(.dragged(NSEvent.mouseLocation))
            return true
        case .leftMouseUp where pressesEye:
            pressesEye = false
            onEyePointer?(.up(NSEvent.mouseLocation))
            return true
        case .scrollWheel where !isExpanded && !eyeHandles.isEmpty:
            onEyeScroll?(event)
            return true
        default:
            return false
        }
    }

    // MARK: Clicks through the window

    private func clickThroughChanged() {
        if clickThroughOutlines == nil {
            stopFollowingPointer()
        } else if pointerMonitors.isEmpty {
            startFollowingPointer()
        }
        followPointer()
    }

    /// Lets the mouse through the window wherever the pointer is off its shapes. A press that went
    /// down in this window keeps the mouse until it is released, so a drag that started here, on the
    /// eye or in the panel, gets its release; one whose release never arrived doesn't hold on to it.
    private func followPointer() {
        let held = pressedHere && NSEvent.pressedMouseButtons & 1 != 0
        let through = clickThroughOutlines.map { !held && !ClickThrough.hits(NSEvent.mouseLocation, $0) } ?? false
        if ignoresMouseEvents != through { ignoresMouseEvents = through }
    }

    private func startFollowingPointer() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPointer() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated { self?.followPointer() }
            return event
        }
        pointerMonitors = [global, local].compactMap { $0 }
        // The window isn't key, so it gets the pointer's moves only through a tracking area.
        if let view = contentView {
            let tracking = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: view,
                userInfo: nil)
            view.addTrackingArea(tracking)
            pointerTracking = tracking
        }
    }

    private func stopFollowingPointer() {
        for monitor in pointerMonitors { NSEvent.removeMonitor(monitor) }
        pointerMonitors = []
        if let pointerTracking { contentView?.removeTrackingArea(pointerTracking) }
        pointerTracking = nil
    }
}

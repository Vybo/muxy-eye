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

    /// The left button went down on the eye and hasn't come up yet.
    private var pressesEye = false

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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A click in the expanded panel gives it the keyboard, also when it expanded on its own. A click
    /// beside the panel (in the window's margin while it animates) neither takes the keyboard nor
    /// reaches the content: it counts as a click outside.
    override func sendEvent(_ event: NSEvent) {
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
}

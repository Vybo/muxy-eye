import AppKit

/// A borderless, non-activating panel above the menu bar that hosts the eye.
final class EyePanel: NSPanel {
    /// Expanded or expanding: a click in it gives it the keyboard.
    var isExpanded = false

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

    /// A click in the expanded panel gives it the keyboard, also when it expanded on its own.
    override func sendEvent(_ event: NSEvent) {
        if isExpanded, event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}

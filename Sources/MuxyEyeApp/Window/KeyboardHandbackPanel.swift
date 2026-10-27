import AppKit

/// Gives the keyboard back to the app the user was in while the eye stays on screen. The eye's panel
/// takes the keyboard without activating Muxy Eye, and gives it back when it stops being the key
/// window. Ordering it out would do that, but the eye would then vanish until its next frame is drawn,
/// a flash as the panel starts to close. So this tiny, invisible panel becomes key in its place and is
/// ordered out at once.
final class KeyboardHandbackPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Like the eye's panel: on every Space and beside full-screen apps, left alone by Mission Control
        // and out of the window cycle. (`.transient` can't be combined with `.stationary`.)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Takes the keyboard from `panel` and gives it up at once, from a point inside `panel` and a level
    /// below it, so nothing of it can show. As this panel goes, AppKit picks the next key window there
    /// and then, and it would pick `panel`, the window that was key before; so `panel` refuses meanwhile.
    func handBack(from panel: EyePanel) {
        panel.refusesKey = true
        defer { panel.refusesKey = false }
        level = NSWindow.Level(rawValue: panel.level.rawValue - 1)
        setFrame(CGRect(x: panel.frame.midX, y: panel.frame.midY, width: 1, height: 1), display: false)
        orderFrontRegardless()
        makeKey()
        orderOut(nil)
    }
}

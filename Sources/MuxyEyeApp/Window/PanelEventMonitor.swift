import AppKit

/// While the panel is expanded, watches for clicks outside it and for the keys it handles as the key window.
@MainActor
final class PanelEventMonitor {
    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }

    private var clickMonitor: Any?
    private var keyMonitor: Any?

    var isRunning: Bool { clickMonitor != nil || keyMonitor != nil }

    func start(
        panel: NSPanel,
        onClickOutside: @escaping @MainActor () -> Void,
        onKey: @escaping @MainActor (PanelKey) -> Void
    ) {
        guard !isRunning else { return }
        // Global monitors only see events delivered to other apps, so every hit is outside the panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            MainActor.assumeIsolated { onClickOutside() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            let handled = MainActor.assumeIsolated {
                guard let panel, event.window === panel, panel.isKeyWindow else { return false }
                let editingText = panel.firstResponder is NSText
                guard let key = Self.key(for: event, editingText: editingText) else { return false }
                onKey(key)
                return true
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        clickMonitor = nil
        keyMonitor = nil
    }

    /// Esc always collapses. While a text field is being edited every other key goes to the field,
    /// so Return sends the field and digits are typed.
    private static func key(for event: NSEvent, editingText: Bool) -> PanelKey? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        if event.keyCode == KeyCode.escape { return .escape }
        guard !editingText else { return nil }
        switch event.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter: return .primary
        case KeyCode.upArrow: return .up
        case KeyCode.downArrow: return .down
        default: break
        }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
              let digit = Int(characters), (1...9).contains(digit)
        else { return nil }
        return .digit(digit)
    }
}

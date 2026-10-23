/// A terminal screen as `muxy session read-screen --json` reports it: the visible rows, one line
/// per row from the top, and the cursor position (0-based row and column).
public struct ScreenState: Sendable, Equatable {
    public var text: String
    public var cursorRow: Int
    public var cursorCol: Int

    public init(text: String, cursorRow: Int, cursorCol: Int) {
        self.text = text
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
    }

    public var cursor: (row: Int, col: Int) { (cursorRow, cursorCol) }

    /// Whether Claude is at its input prompt with nothing typed (a dim suggestion may be shown).
    public var isAtIdlePrompt: Bool { ScreenParser.isAtIdlePrompt(text, cursor: cursor) }
}

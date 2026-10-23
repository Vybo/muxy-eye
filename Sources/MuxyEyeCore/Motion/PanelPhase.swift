import CoreGraphics

/// Where the expanded panel is in its open/close cycle.
public enum PanelPhase: Sendable, Equatable {
    case collapsed, opening, expanded, closing

    /// The phase once the panel is asked to expand or collapse. A request against the running
    /// transition turns it around from where it is; a request it already heads for changes nothing.
    public func requesting(expanded: Bool) -> PanelPhase {
        switch (self, expanded) {
        case (.collapsed, true), (.closing, true): .opening
        case (.expanded, false), (.opening, false): .closing
        default: self
        }
    }

    /// The phase once the running transition has finished.
    public var settled: PanelPhase {
        switch self {
        case .opening: .expanded
        case .closing: .collapsed
        case .collapsed, .expanded: self
        }
    }

    /// Heading for, or at, the expanded panel.
    public var isExpanding: Bool { self == .opening || self == .expanded }

    /// The expanded panel is drawn: everywhere but at rest collapsed.
    public var showsPanel: Bool { self != .collapsed }

    /// The collapsed eye's signal line and count are drawn: everywhere but at rest expanded.
    public var showsEye: Bool { self != .expanded }

    /// What is visible once this phase has settled, on screen: the collapsed eye and, while
    /// expanding, the panel over it.
    public func footprint(collapsed: CollapsedLayout, expanded: CGRect) -> CGRect {
        isExpanding ? expanded.union(collapsed.panelFrame) : collapsed.panelFrame
    }
}

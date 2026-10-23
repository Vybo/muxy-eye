import Foundation

/// The prompt a key press is for: the session the panel shows when the key goes down and the
/// prompt it shows for that session. Only a view showing that same prompt may act on the key, so
/// a view that is fading out after the selection moved on, or one whose prompt was just replaced,
/// can't answer it.
public struct PromptTarget: Sendable, Equatable {
    public var session: MuxySessionID
    public var pending: PendingItem?

    public init(session: MuxySessionID, pending: PendingItem?) {
        self.session = session
        self.pending = pending
    }

    /// What the panel shows in `state` with `selected` selected.
    public static func displayed(in state: EyeState, selected: MuxySessionID?) -> PromptTarget? {
        guard let record = state.displayedRecord(selected: selected) else { return nil }
        return PromptTarget(session: record.id, pending: record.pending)
    }

    /// Whether a view showing `pending` for `session` may act on a key aimed here: the same
    /// session and the same prompt (whether Muxy has seen it blocked yet doesn't matter).
    public func matches(session: MuxySessionID, pending: PendingItem) -> Bool {
        guard session == self.session, let target = self.pending else { return false }
        return target.isSamePrompt(as: pending)
    }
}

extension EyeState {
    /// The session the expanded panel shows: the selected one, or the rail's first when none is
    /// selected or the selected one has gone.
    public func displayedRecord(selected: MuxySessionID?) -> SessionRecord? {
        selected.flatMap { sessions[$0] } ?? rail.first
    }
}

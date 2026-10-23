import Foundation

/// The words the expanded panel shows for a session: rail subtitles, kind labels, names and
/// the read-only screen excerpt.
public enum SessionPresentation {
    /// A compact age in the largest whole unit: `40s`, `2m`, `3h`, `1d`.
    public static func age(_ interval: TimeInterval) -> String {
        let seconds = interval.isFinite ? max(0, Int(interval)) : 0
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }

    /// `approval · 2m`, `question · 40s`, `finished · 10s`, `needs input · 5s`, `working` or `idle`
    /// for Claude; `<provider> · <state>` for other agents, which have state only.
    public static func railSubtitle(for record: SessionRecord, in state: EyeState, now: Date) -> String {
        let status = status(of: record, in: state)
        guard record.isClaude else { return "\(record.provider) · \(status)" }
        guard state.isWaiting(record), let since = state.waitingSince(record) else { return status }
        return "\(status) · \(age(now.timeIntervalSince(since)))"
    }

    /// The orange caps label above a waiting session's prompt; nil when the session isn't waiting.
    public static func kindLabel(for record: SessionRecord, in state: EyeState, screen: ScreenPrompt?) -> String? {
        if let pending = record.pending {
            switch pending.kind {
            case .permission(let request):
                return request.title.uppercased()
            case .question(let request):
                let header = (request.current(on: screen) ?? request.questions.first)?.header
                    .trimmingCharacters(in: .whitespaces) ?? ""
                return header.isEmpty ? "QUESTION" : "QUESTION · \(header.uppercased())"
            case .finished:
                return "FINISHED"
            }
        }
        guard state.isWaiting(record) else { return nil }
        return isUnreadCompletion(record) ? "FINISHED" : "NEEDS INPUT"
    }

    /// The last `lines` non-empty lines of a `read-screen` capture, without trailing whitespace.
    public static func screenTail(_ screen: String, lines count: Int = 15) -> [String] {
        let lines = screen.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).compactMap { line -> String? in
            var text = Substring(line)
            while text.last?.isWhitespace == true { text.removeLast() }
            return text.isEmpty ? nil : String(text)
        }
        return Array(lines.suffix(max(count, 0)))
    }

    /// The project name, else the session directory's name, else the provider.
    public static func displayName(for record: SessionRecord) -> String {
        if !record.projectName.isEmpty { return record.projectName }
        if let directory = record.directory {
            let name = (directory as NSString).lastPathComponent
            if !name.isEmpty, name != "/" { return name }
        }
        return record.provider
    }

    /// The detail header's second line: `<worktree> · <provider>`, or just the provider.
    public static func headerDetail(for record: SessionRecord) -> String {
        [record.subtitle, record.provider]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func status(of record: SessionRecord, in state: EyeState) -> String {
        if let pending = record.pending {
            switch pending.kind {
            case .permission: return "approval"
            case .question: return "question"
            case .finished: return "finished"
            }
        }
        if record.muxyState == .blocked { return "needs input" }
        if state.isWaiting(record) { return "finished" }
        return record.muxyState == .working ? "working" : "idle"
    }

    private static func isUnreadCompletion(_ record: SessionRecord) -> Bool {
        record.muxyState != .blocked && record.unreadCompletedEventID != nil
    }
}

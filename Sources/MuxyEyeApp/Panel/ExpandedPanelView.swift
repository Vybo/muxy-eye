import MuxyEyeCore
import SwiftUI

/// The expanded panel's content: the sessions rail on the left and the selected session's prompt on
/// the right, over the panel's black shape (drawn by the stage). It reports the height it wants
/// through `onHeightChange`. It cascades in once it is on screen, and fades out when `contentShown` turns false.
struct ExpandedPanelView: View {
    static let railWidth: CGFloat = 150
    private static let minContentHeight: CGFloat = 150

    let model: AppModel
    /// Room left at the top for the physical notch; the background still covers it.
    let topInset: CGFloat
    /// The panel is open or opening; false while it closes.
    let contentShown: Bool
    let onHeightChange: (CGFloat) -> Void

    @State private var railHeight: CGFloat = 0
    @State private var detailHeight: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        let motion = PanelMotion()
        let revealed = appeared && contentShown
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            content(revealed: revealed, motion: motion)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .reveal(revealed, show: motion.contentIn, hide: motion.contentOut)
        .environment(\.colorScheme, .dark)
        .onChange(of: desiredHeight, initial: true) { _, height in onHeightChange(height) }
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func content(revealed: Bool, motion: PanelMotion) -> some View {
        let state = model.state
        if let record = selectedRecord {
            HStack(alignment: .top, spacing: 0) {
                SessionRailView(model: model, revealed: revealed) { railHeight = $0 }
                    .frame(width: Self.railWidth)
                Rectangle()
                    .fill(PanelTheme.divider)
                    .frame(width: 1)
                // Another session's detail cross-fades in over the last one.
                ZStack(alignment: .topLeading) {
                    SessionDetailView(model: model, record: record)
                        .id(record.id)
                        .transition(.opacity)
                }
                .animation(motion.detailSwap.animation, value: record.id)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailHeight = $0 }
                .reveal(revealed, show: motion.detailIn, hide: motion.contentOut, slide: motion.contentSlide)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        } else {
            Text(state.muxyRunning ? "No agent sessions in Muxy" : AppModel.muxyNotRunningReason)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailHeight = $0 }
        }
    }

    private var selectedRecord: SessionRecord? {
        let state = model.state
        return model.selectedSession.flatMap { state.sessions[$0] } ?? state.rail.first
    }

    private var desiredHeight: CGFloat {
        let content = selectedRecord == nil ? detailHeight : max(Self.minContentHeight, railHeight, detailHeight)
        return (topInset + content).rounded(.up)
    }
}

/// The right side: header, kind label, banner, the prompt for the session's state, and Open in Muxy.
private struct SessionDetailView: View {
    private static let screenAttempts = 5
    private static let screenRetryDelay: Duration = .milliseconds(400)

    let model: AppModel
    let record: SessionRecord

    var body: some View {
        let state = model.state
        let screenText = model.latestScreen[record.id]?.text
        let screen = screenText.flatMap(ScreenParser.parse)
        let waiting = state.isWaiting(record)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: SessionPresentation.displayName(for: record))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PanelTheme.text)
                Text(verbatim: SessionPresentation.headerDetail(for: record))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.secondaryText)
            }
            .lineLimit(1)

            if let label = SessionPresentation.kindLabel(for: record, in: state, screen: screen) {
                Text(verbatim: label)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(PanelTheme.waiting)
                    .lineLimit(1)
            }

            if let message = AnswerBanner.message(for: model.lastOutcome[record.id]) {
                BannerView(message: message, action: openInMuxy)
            }

            prompt(screenText: screenText, screen: screen, waiting: waiting)

            OpenInMuxyButton(action: openInMuxy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: ScreenLoadKey(record: record, waiting: waiting)) {
            guard waiting else { return }
            await loadScreen()
        }
    }

    @ViewBuilder
    private func prompt(screenText: String?, screen: ScreenPrompt?, waiting: Bool) -> some View {
        if record.isClaude, let pending = record.pending {
            Group {
                switch pending.kind {
                case .permission(let request):
                    PermissionDetailView(model: model, session: record.id, request: request, pending: pending, screen: screen)
                case .question(let request):
                    QuestionDetailView(model: model, session: record.id, request: request, pending: pending, screen: screen)
                case .finished(let message):
                    FinishedDetailView(model: model, session: record.id, pending: pending, message: message)
                }
            }
            .id(pending.receivedAt)
        } else if waiting {
            ScreenFallbackView(screen: screenText)
        } else {
            SessionStatusView(record: record)
        }
    }

    /// Reads the screen, retrying briefly while it doesn't show the pending prompt yet
    /// (the hook can arrive before Claude draws its dialog).
    private func loadScreen() async {
        for attempt in 1...Self.screenAttempts {
            await model.loadScreen(record.id)
            if attempt == Self.screenAttempts || model.screenShowsPending(record.id) { return }
            do {
                try await Task.sleep(for: Self.screenRetryDelay)
            } catch {
                return
            }
        }
    }

    private func openInMuxy() {
        let session = record.id
        Task { await model.openInMuxy(session) }
    }
}

/// What makes the selected session's screen worth reading again.
private struct ScreenLoadKey: Equatable {
    let session: MuxySessionID
    let pending: PendingItem?
    let muxyState: AgentState
    let waiting: Bool

    init(record: SessionRecord, waiting: Bool) {
        session = record.id
        pending = record.pending
        muxyState = record.muxyState
        self.waiting = waiting
    }
}

/// A working or idle session: its status and, for Claude, the last assistant message.
private struct SessionStatusView: View {
    private static let messageMaxHeight: CGFloat = 120

    let record: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.muxyState == .working ? "Working" : "Idle")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(PanelTheme.secondaryText)
            if record.isClaude, let message = record.lastAssistantMessage, !message.isEmpty {
                AssistantMessageView(message: message, maxHeight: Self.messageMaxHeight)
            }
        }
    }
}

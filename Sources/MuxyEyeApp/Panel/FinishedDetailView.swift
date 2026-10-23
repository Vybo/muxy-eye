import MuxyEyeCore
import SwiftUI

/// A finished turn: Claude's last message, a reply field, and Dismiss.
struct FinishedDetailView: View {
    private static let messageMaxHeight: CGFloat = 120

    let model: AppModel
    let session: MuxySessionID
    let message: String?

    @State private var reply = ""

    var body: some View {
        let busy = model.answering.contains(session)
        VStack(alignment: .leading, spacing: 8) {
            AssistantMessageView(message: message, maxHeight: Self.messageMaxHeight)
            HStack(spacing: 6) {
                AnswerField(placeholder: "Reply to Claude…", text: $reply, disabled: busy) {
                    send(.reply(reply))
                }
                PanelButton(title: "Dismiss") {
                    model.dismiss(session)
                }
            }
        }
    }

    private func send(_ answer: UserAnswer) {
        Task {
            await model.answer(answer, for: session)
            if model.lastOutcome[session] == .delivered { reply = "" }
        }
    }
}

/// Claude's last message in a card, scrollable past `maxHeight`.
struct AssistantMessageView: View {
    let message: String?
    let maxHeight: CGFloat

    var body: some View {
        CappedScrollView(maxHeight: maxHeight) {
            Text(verbatim: message ?? "Claude finished its turn.")
                .font(.system(size: 12.5))
                .foregroundStyle(message == nil ? PanelTheme.secondaryText : PanelTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(PanelTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

import MuxyEyeCore
import SwiftUI

/// A permission approval: the command or file, its description, and the options read from the screen.
/// When the screen doesn't show this prompt, no answer controls are offered.
struct PermissionDetailView: View {
    private static let commandMaxHeight: CGFloat = 120

    let model: AppModel
    let session: MuxySessionID
    let request: PermissionRequest
    let pending: PendingItem
    let screen: ScreenPrompt?
    let keyPress: PanelKeyPress?

    @Environment(\.isLeaving) private var leaving
    @Environment(\.answerGate) private var answerGate

    @State private var feedback = ""
    /// How often each option has been picked, to flash it each time.
    @State private var flashes: [Int: Int] = [:]

    var body: some View {
        let options = answerableOptions
        let busy = model.answering.contains(session)
        VStack(alignment: .leading, spacing: 8) {
            if let primary = request.primaryText {
                MonospaceCard {
                    CappedScrollView(maxHeight: Self.commandMaxHeight) {
                        Text(verbatim: primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let detail = request.detail, !detail.isEmpty {
                InlineMarkdown.text(detail, fontSize: 12)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !options.isEmpty {
                VStack(spacing: 4) {
                    ForEach(options, id: \.number) { option in
                        OptionButton(
                            number: option.number,
                            label: option.label,
                            isDefault: option.number == 1,
                            disabled: busy,
                            flash: flashes[option.number, default: 0]
                        ) {
                            pick(option.number)
                        }
                    }
                }
                if AnswerPlanner.denyOption(on: screen) != nil {
                    AnswerField(placeholder: "Tell Claude what to do instead…", text: $feedback, disabled: busy) {
                        send(.deny(feedback: feedback))
                    }
                }
            }
        }
        .onChange(of: keyPress) { _, press in
            // Only keys pressed while this prompt was the one on show, and never while it fades out.
            guard let press, !leaving, press.isFor(session: session, pending: pending), !options.isEmpty else { return }
            switch press.kind {
            case .digit(let number):
                if options.contains(where: { $0.number == number }) { pick(number) }
            case .primary:
                if options.contains(where: { $0.number == 1 }) { pick(1) }
            }
        }
    }

    /// The screen's numbered options, only while the screen still shows this prompt.
    private var answerableOptions: [ScreenOption] {
        guard AnswerPlanner.matches(pending, screen: screen, idlePrompt: false),
              case .permission(_, _, _, let options)? = screen
        else { return [] }
        return options
    }

    /// Flashes the picked option, unless an answer is already going out, and sends it.
    private func pick(_ number: Int) {
        guard answersAllowed else { return }
        if !model.answering.contains(session) { flashes[number, default: 0] += 1 }
        send(.option(number))
    }

    /// Not until the prompt has faded in, and never while it fades out: the eye answers only what the
    /// user sees.
    private var answersAllowed: Bool { !leaving && answerGate.allowsAnswer(at: .now) }

    private func send(_ answer: UserAnswer) {
        guard answersAllowed else { return }
        Task {
            await model.answer(answer, to: pending, for: session)
            if model.lastOutcome[session] == .delivered { feedback = "" }
        }
    }
}

import MuxyEyeCore
import SwiftUI

/// A question from Claude, shown one at a time in terminal order. Single-select offers the hook's
/// options and a free-text field; multi-select offers checkboxes and Submit. When the screen
/// doesn't show the question, only its text is shown.
struct QuestionDetailView: View {
    let model: AppModel
    let session: MuxySessionID
    let request: QuestionRequest
    let pending: PendingItem
    let screen: ScreenPrompt?
    let keyPress: PanelKeyPress?

    @Environment(\.isLeaving) private var leaving

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Set<Int> = []
    @State private var freeText = ""
    /// How often each option, and Submit, has sent an answer, to flash it each time.
    @State private var flashes: [Int: Int] = [:]
    @State private var submitFlashes = 0

    var body: some View {
        let current = answerableQuestion
        let shown = current ?? request.current(on: screen) ?? request.questions.first
        let busy = model.answering.contains(session)
        let motion = PanelMotion(reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: 8) {
            // The next of several questions fades in over the one just answered. Only the text is
            // swapped: the controls stay, so a field that has focus keeps it.
            ZStack(alignment: .topLeading) {
                if let shown {
                    Text(verbatim: shown.question)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PanelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(shown.question)
                        .transition(motion.transition(.opacity))
                }
            }
            .animation(motion.promptSwap?.animation, value: shown?.question)
            if let current {
                if isMultiSelect {
                    multiSelect(current, busy: busy)
                } else {
                    singleSelect(current, busy: busy)
                }
            }
        }
        .onChange(of: current?.question, initial: true) {
            selection = checkedOnScreen(limit: current?.options.count ?? 0)
        }
        .onChange(of: keyPress) { _, press in
            // Only keys pressed while this prompt was the one on show, and never while it fades out.
            guard let press, !leaving, press.isFor(session: session, pending: pending), let current else { return }
            handle(press.kind, question: current)
        }
    }

    @ViewBuilder
    private func singleSelect(_ question: Question, busy: Bool) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                OptionButton(
                    number: index + 1,
                    label: option.label,
                    description: option.description,
                    isDefault: index == 0,
                    disabled: busy,
                    flash: flashes[index + 1, default: 0]
                ) {
                    pick(index + 1, in: question)
                }
            }
        }
        if AnswerPlanner.freeTextOption(on: screen) != nil {
            AnswerField(placeholder: "Type something else…", text: $freeText, disabled: busy) {
                send(.freeText(freeText), to: question)
            }
        }
    }

    @ViewBuilder
    private func multiSelect(_ question: Question, busy: Bool) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                CheckboxRow(
                    number: index + 1,
                    label: option.label,
                    description: option.description,
                    checked: selection.contains(index + 1),
                    disabled: busy
                ) {
                    toggle(index + 1)
                }
            }
        }
        HStack {
            Spacer()
            PanelButton(title: "Submit", disabled: selection.isEmpty || busy, flash: submitFlashes) {
                submit(question)
            }
        }
    }

    /// The question on screen, only while the screen still shows this prompt.
    private var answerableQuestion: Question? {
        guard AnswerPlanner.matches(pending, screen: screen, idlePrompt: false) else { return nil }
        return request.current(on: screen)
    }

    private var isMultiSelect: Bool {
        if case .question(_, _, _, let isMulti)? = screen { return isMulti }
        return false
    }

    private func checkedOnScreen(limit: Int) -> Set<Int> {
        guard case .question(_, _, let options, true)? = screen else { return [] }
        return Set(options.filter { $0.number <= limit && $0.checked == true }.map(\.number))
    }

    private func handle(_ key: PanelKeyPress.Kind, question: Question) {
        let count = question.options.count
        guard !model.answering.contains(session) else { return }
        switch key {
        case .digit(let number):
            guard number >= 1, number <= count else { return }
            if isMultiSelect { toggle(number) } else { pick(number, in: question) }
        case .primary:
            if isMultiSelect {
                if !selection.isEmpty { submit(question) }
            } else if count > 0 {
                pick(1, in: question)
            }
        }
    }

    /// Flashes the picked option, unless an answer is already going out, and sends it.
    private func pick(_ number: Int, in question: Question) {
        if !model.answering.contains(session) { flashes[number, default: 0] += 1 }
        send(.option(number), to: question)
    }

    private func submit(_ question: Question) {
        if !model.answering.contains(session) { submitFlashes += 1 }
        send(.multiSelect(selection), to: question)
    }

    private func toggle(_ number: Int) {
        if selection.contains(number) { selection.remove(number) } else { selection.insert(number) }
    }

    /// Sends an answer bound to the question shown, so it can't land on another question of the request.
    private func send(_ answer: UserAnswer, to question: Question) {
        Task {
            await model.answer(answer, to: pending, question: question.question, for: session)
            if model.lastOutcome[session] == .delivered { freeText = "" }
        }
    }
}

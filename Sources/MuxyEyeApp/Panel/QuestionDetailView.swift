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

    @State private var selection: Set<Int> = []
    @State private var freeText = ""

    var body: some View {
        let current = answerableQuestion
        let shown = current ?? request.current(on: screen) ?? request.questions.first
        let busy = model.answering.contains(session)
        VStack(alignment: .leading, spacing: 8) {
            if let shown {
                Text(verbatim: shown.question)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .onChange(of: model.keyPress) { _, press in
            guard let press, let current else { return }
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
                    disabled: busy
                ) {
                    send(.option(index + 1), to: question)
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
            PanelButton(title: "Submit", disabled: selection.isEmpty || busy) {
                send(.multiSelect(selection), to: question)
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
            if isMultiSelect { toggle(number) } else { send(.option(number), to: question) }
        case .primary:
            if isMultiSelect {
                if !selection.isEmpty { send(.multiSelect(selection), to: question) }
            } else if count > 0 {
                send(.option(1), to: question)
            }
        }
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

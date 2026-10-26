import MuxyEyeCore
import SwiftUI

/// The inline message shown after an answer the eye couldn't deliver.
enum AnswerBanner {
    static func message(for outcome: AnswerOutcome?) -> String? {
        switch outcome {
        case nil, .delivered?, .busy?:
            nil
        case .promptChanged?, .unsupported?:
            "Prompt changed — Open in Muxy"
        case .notConfirmed?:
            "Couldn't confirm — Open in Muxy"
        case .failed(let reason)?:
            reason == AppModel.muxyNotRunningReason ? reason : "Couldn't confirm — Open in Muxy"
        }
    }
}

/// A numbered answer row: the label, an optional description, and the orange fill for the default.
struct OptionButton: View {
    let number: Int
    let label: String
    var description: String?
    var isDefault = false
    var disabled = false
    /// Changes each time the option is picked, which flashes it.
    var flash = 0
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .opacity(0.7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                    if let description, !description.isEmpty {
                        Text(verbatim: description)
                            .font(.system(size: 11))
                            .foregroundStyle(isDefault ? Color.black.opacity(0.7) : PanelTheme.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDefault ? Color.black : PanelTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isDefault ? PanelTheme.waiting : PanelTheme.card, in: shape)
            .answerFlash(flash, cornerRadius: 8, flash: PanelMotion().answerFlash)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

/// A multi-select row with a checkbox.
struct CheckboxRow: View {
    let number: Int
    let label: String
    var description: String?
    let checked: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(checked ? PanelTheme.waiting : PanelTheme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(PanelTheme.text)
                        .lineLimit(2)
                    if let description, !description.isEmpty {
                        Text(verbatim: description)
                            .font(.system(size: 11))
                            .foregroundStyle(PanelTheme.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PanelTheme.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

/// A one-line text field with a send button; Return in the field sends too.
struct AnswerField: View {
    let placeholder: String
    @Binding var text: String
    var actionTitle = "Send"
    var disabled = false
    let onSend: () -> Void

    var body: some View {
        let empty = AnswerText.sanitized(text) == nil
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(PanelTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(PanelTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(disabled)
                .onSubmit {
                    if !empty, !disabled { onSend() }
                }
            PanelButton(title: actionTitle, disabled: empty || disabled, action: onSend)
        }
    }
}

/// A small secondary button on the card colour.
struct PanelButton: View {
    let title: String
    var disabled = false
    /// Changes each time the button sends an answer, which flashes it.
    var flash = 0
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PanelTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(PanelTheme.divider, in: shape)
                .answerFlash(flash, cornerRadius: 8, flash: PanelMotion().answerFlash)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

struct OpenInMuxyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Open in Muxy ↗")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PanelTheme.link)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The eye's menu as a button in the expanded panel: menu-bar tools can take right clicks on the eye.
struct PanelMenuButton: View {
    /// The whole square takes clicks, not just the three dots.
    static let width: CGFloat = 32

    let model: AppModel

    var body: some View {
        Menu {
            EyeMenu(model: model)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PanelTheme.secondaryText)
                .frame(width: Self.width, height: Self.width)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Muxy Eye menu")
        .accessibilityLabel("Muxy Eye menu")
    }
}

/// The inline banner after an undelivered answer; clicking it opens Muxy.
struct BannerView: View {
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PanelTheme.waiting)
                Text(message)
                    .foregroundStyle(PanelTheme.text)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(PanelTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Shows its content at natural height up to `maxHeight`, and scrolls beyond that.
struct CappedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(contentHeight > maxHeight ? .automatic : .never)
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }
}

/// A monospaced card, used for commands and terminal lines.
struct MonospaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(PanelTheme.text)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

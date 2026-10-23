import MuxyEyeCore
import SwiftUI

/// The collapsed eye: a black circle (or the widened notch) with the signal line and the waiting count.
struct CollapsedEyeView: View {
    private static let notchCornerRadius: CGFloat = 10

    let model: AppModel
    let layout: CollapsedLayout

    var body: some View {
        let size = layout.panelFrame.size
        let state = model.state
        ZStack {
            if let shape = layout.shapeFrame {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: Self.notchCornerRadius,
                    bottomTrailingRadius: Self.notchCornerRadius,
                    style: .continuous
                )
                .fill(PanelTheme.eye)
                .place(in: shape, panelHeight: size.height)
            } else {
                Capsule()
                    .fill(PanelTheme.eye)
                    .place(in: layout.eyeFrame, panelHeight: size.height)
            }

            SignalLineEyeView(mode: state.mode)
                .place(in: layout.eyeFrame, panelHeight: size.height)

            if let countFrame = layout.countFrame {
                Text("\(state.waitingCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(PanelTheme.waiting)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: countFrame.width, height: countFrame.height)
                    .background(Capsule().fill(PanelTheme.eye))
                    .place(in: countFrame, panelHeight: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { model.expand(focus: true) }
    }
}

private extension View {
    /// Places the view at `rect`, given in AppKit panel coordinates (origin at the bottom left).
    func place(in rect: CGRect, panelHeight: CGFloat) -> some View {
        frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: panelHeight - rect.midY)
    }
}

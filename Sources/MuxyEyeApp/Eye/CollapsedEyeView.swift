import MuxyEyeCore
import SwiftUI

/// The collapsed eye: a black circle (or the widened notch) with the signal line and the waiting count.
/// Only the visible shapes take clicks; the transparent rest of the panel does not.
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
                .allowsHitTesting(false)
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
                    .contentShape(Capsule())
                    .place(in: countFrame, panelHeight: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .onTapGesture { model.expand(focus: true) }
        .contextMenu {
            Button("Settings…") { model.openSettings() }
            Button("Hide for 1 Hour") { model.hidePanel(for: .seconds(3600)) }
            Divider()
            Button("Quit Muxy Eye") { NSApp.terminate(nil) }
        }
    }
}

private extension View {
    /// Places the view at `rect`, given in AppKit panel coordinates (origin at the bottom left).
    func place(in rect: CGRect, panelHeight: CGFloat) -> some View {
        frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: panelHeight - rect.midY)
    }
}

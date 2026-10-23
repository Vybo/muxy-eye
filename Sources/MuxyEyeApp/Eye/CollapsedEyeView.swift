import MuxyEyeCore
import SwiftUI

/// The collapsed eye's black shape: a circle, or the widened notch. A click on it expands the panel.
/// Only the visible shapes take clicks; the transparent rest of the stage does not.
struct CollapsedEyeShape: View {
    let model: AppModel
    let stage: EyeStage

    var body: some View {
        let outline = stage.local(EyeLayout.collapsedOutline(stage.collapsed))
        OutlineShape(outline: outline)
            .fill(PanelTheme.eye)
            .animation(stage.collapsedMotion, value: outline)
            .onTapGesture { model.expand(focus: true) }
            .contextMenu { EyeMenu(model: model) }
    }
}

/// The collapsed eye's signal line and, with something waiting, the count. They sit over the panel's
/// shape, so they dissolve into it as it grows out of the eye and come back as it lands.
struct CollapsedEyeGlyphs: View {
    let model: AppModel
    let stage: EyeStage

    @State private var appeared = false

    var body: some View {
        let layout = stage.collapsed
        let state = model.state
        let motion = PanelMotion()
        let visible = appeared && !stage.phase.isExpanding
        ZStack(alignment: .topLeading) {
            SignalLineEyeView(mode: state.mode)
                .allowsHitTesting(false)
                .place(in: stage.local(layout.onScreen(layout.eyeFrame)))

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
                    .onTapGesture { model.expand(focus: true) }
                    .contextMenu { EyeMenu(model: model) }
                    .place(in: stage.local(layout.onScreen(countFrame)))
            }
        }
        .animation(stage.collapsedMotion, value: layout)
        .reveal(visible, show: motion.eyeIn, hide: motion.eyeOut)
        .allowsHitTesting(visible)
        .onAppear { appeared = true }
    }
}

/// The eye's context menu.
struct EyeMenu: View {
    let model: AppModel

    var body: some View {
        Button("Settings…") { model.openSettings() }
        Button("Hide for 1 Hour") { model.hidePanel(for: .seconds(3600)) }
        Divider()
        Button("Quit Muxy Eye") { NSApp.terminate(nil) }
    }
}

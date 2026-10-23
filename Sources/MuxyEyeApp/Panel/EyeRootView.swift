import MuxyEyeCore
import SwiftUI

/// Everything the eye draws, laid out on the stage: the collapsed eye's shape; the panel's shape,
/// which grows out of it and pulls back into it; the eye's signal line and count over that; and the
/// panel's content, clipped to the panel's shape. The window shows the part that is visible.
struct EyeRootView: View {
    let model: AppModel
    let stage: EyeStage
    let onExpandedHeight: (CGFloat) -> Void

    var body: some View {
        let size = stage.frame.size
        let phase = stage.phase
        ZStack(alignment: .topLeading) {
            CollapsedEyeShape(model: model, stage: stage)
            PanelBackground(model: model, stage: stage)
            if phase.showsEye {
                CollapsedEyeGlyphs(model: model, stage: stage)
            }
            if phase.showsPanel {
                PanelContent(model: model, stage: stage, onExpandedHeight: onExpandedHeight)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

/// The panel's black shape. At rest collapsed it sits, hidden, on the eye's shape; a click on it while
/// it pulls back into the eye opens the panel again.
private struct PanelBackground: View {
    let model: AppModel
    let stage: EyeStage

    var body: some View {
        let outline = stage.local(stage.panelOutline)
        let closing = stage.phase == .closing
        OutlineShape(outline: outline)
            .fill(PanelTheme.background)
            .animation(stage.panelMotion, value: outline)
            .opacity(stage.panelOpacity)
            .animation(stage.panelOpacityMotion, value: stage.panelOpacity)
            .allowsHitTesting(stage.phase.showsPanel)
            .onTapGesture {
                if closing { model.expand(focus: true) }
            }
    }
}

/// The expanded panel's content at the panel's frame, clipped to the panel's shape as it moves.
/// It takes clicks only while the panel is open or opening, never while it fades away.
private struct PanelContent: View {
    let model: AppModel
    let stage: EyeStage
    let onExpandedHeight: (CGFloat) -> Void

    var body: some View {
        let size = stage.frame.size
        let frame = stage.local(stage.expandedFrame)
        let outline = stage.local(stage.panelOutline)
        let expanding = stage.phase.isExpanding
        ZStack(alignment: .topLeading) {
            ExpandedPanelView(
                model: model,
                topInset: stage.topInset,
                contentShown: expanding,
                onHeightChange: onExpandedHeight
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            OutlineShape(outline: outline)
                .animation(stage.panelMotion, value: outline)
        }
        .opacity(stage.panelOpacity)
        .animation(stage.panelOpacityMotion, value: stage.panelOpacity)
        .allowsHitTesting(expanding)
    }
}

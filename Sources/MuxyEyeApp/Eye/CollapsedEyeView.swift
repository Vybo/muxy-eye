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
                let rect = stage.local(layout.onScreen(countFrame))
                CountBadge(count: state.waitingCount, pop: motion.countPop)
                    .onTapGesture { model.expand(focus: true) }
                    .contextMenu { EyeMenu(model: model) }
                    .place(in: rect)
                    .transition(Self.badgeTransition(at: rect, in: stage.frame.size))
            }
        }
        .animation(stage.collapsedMotion, value: layout)
        .reveal(visible, show: motion.eyeIn, hide: motion.eyeOut)
        .allowsHitTesting(visible)
        .onAppear { appeared = true }
    }

    /// The badge grows in from its centre. Placed views span the stage, so the anchor is the badge's
    /// centre as a fraction of the stage.
    private static func badgeTransition(at rect: CGRect, in size: CGSize) -> AnyTransition {
        guard size.width > 0, size.height > 0 else { return .opacity }
        let anchor = UnitPoint(x: rect.midX / size.width, y: rect.midY / size.height)
        return .scale(scale: 0.5, anchor: anchor).combined(with: .opacity)
    }
}

/// The waiting count: orange on a black capsule, which on a notch display sits on the right wing.
/// It pops briefly when the count changes.
private struct CountBadge: View {
    let count: Int
    let pop: Pop?

    var body: some View {
        let badge = Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(PanelTheme.waiting)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(PanelTheme.eye))
            .contentShape(Capsule())
        if let pop {
            badge.keyframeAnimator(initialValue: CGFloat(1), trigger: count) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(pop.scale, duration: pop.rise)
                CubicKeyframe(1, duration: pop.fall)
            }
        } else {
            badge
        }
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

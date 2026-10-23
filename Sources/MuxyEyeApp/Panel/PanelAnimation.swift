import MuxyEyeCore
import SwiftUI

extension Motion {
    var animation: Animation {
        let base: Animation = switch curve {
        case .spring(let response, let damping): .spring(response: response, dampingFraction: damping)
        case .easeOut(let duration): .easeOut(duration: duration)
        case .easeInOut(let duration): .easeInOut(duration: duration)
        case .decelerate(let duration): .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
        }
        return delay > 0 ? base.delay(delay) : base
    }
}

extension PanelMotion {
    /// `base`, or under Reduce Motion a plain fade that runs on its own, so the views around it
    /// don't move while it fades.
    func transition(_ base: AnyTransition) -> AnyTransition {
        guard let fade = transitionFade else { return base }
        return .opacity.animation(fade.animation)
    }
}

extension View {
    /// Fades the view in (sliding down `slide` points) with `show` while `visible`, out with `hide`.
    func reveal(_ visible: Bool, show: Motion?, hide: Motion?, slide: CGFloat = 0) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -slide)
            .animation((visible ? show : hide)?.animation, value: visible)
    }

    /// Lights the view up briefly, as a rounded rectangle, each time `trigger` changes.
    func answerFlash(_ trigger: Int, cornerRadius: CGFloat, flash: Flash) -> some View {
        modifier(AnswerFlash(trigger: trigger, cornerRadius: cornerRadius, flash: flash))
    }

    /// Places the view at `rect`, in the top-left coordinates of the stage it is drawn on.
    func place(in rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

/// The highlight of a picked answer. Nothing runs between flashes.
private struct AnswerFlash: ViewModifier {
    let trigger: Int
    let cornerRadius: CGFloat
    let flash: Flash

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, opacity in
            view.overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(opacity))
                    .allowsHitTesting(false)
            }
        } keyframes: { _ in
            LinearKeyframe(flash.opacity, duration: flash.rise)
            LinearKeyframe(0, duration: flash.fall)
        }
    }
}

/// One of the eye's black shapes: an outline in the stage's coordinates, which animates as a whole
/// (frame and corners), so the eye can morph into the panel and back.
struct OutlineShape: Shape {
    var outline: EyeOutline

    nonisolated var animatableData: AnimatablePair<CGRect.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(outline.frame.animatableData, AnimatablePair(outline.topRadius, outline.bottomRadius))
        }
        set {
            outline.frame.animatableData = newValue.first
            outline.topRadius = newValue.second.first
            outline.bottomRadius = newValue.second.second
        }
    }

    nonisolated func path(in _: CGRect) -> Path {
        let rect = outline.frame.standardized
        // A spring overshoots its corners too; keep them between square and fully round.
        let limit = max(0, min(rect.width, rect.height) / 2)
        let top = min(max(outline.topRadius, 0), limit)
        let bottom = min(max(outline.bottomRadius, 0), limit)
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
        .path(in: rect)
    }
}
